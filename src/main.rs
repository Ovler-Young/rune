use clap::{ArgGroup, Parser, Subcommand};
use prettytable::{format, row, Table};
use serde_json::json;
use std::fs::canonicalize;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use tracing_subscriber::filter::EnvFilter;

use database::actions::analysis::analysis_audio_library;
use database::actions::file::get_file_id_from_path;
use database::actions::file::get_files_by_ids;
use database::actions::metadata::scan_audio_library;
use database::actions::recommendation::get_recommendation;
use database::actions::recommendation::sync_recommendation;
use database::connection::{connect_main_db, connect_recommendation_db};

#[derive(Parser)]
#[command(name = "Media Manager")]
#[command(about = "A CLI tool for managing media libraries", long_about = None)]
#[command(group(ArgGroup::new("library_group").required(true).args(&["library", "library0"])))]
struct Cli {
    /// The root path of the media library (option)
    #[arg(short, long)]
    library: Option<PathBuf>,

    /// The root path of the media library (positional)
    #[arg()]
    library0: Option<PathBuf>,

    /// The subcommand to run
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Scan the audio library
    Scan,

    /// Analyze the audio files in the library
    Analyze,

    /// Recommend music
    Recommend {
        /// The ID of the item to get recommendations for
        #[arg(short, long, group = "recommend_group")]
        item_id: Option<usize>,

        /// The file path of the music to get recommendations for
        #[arg(short = 'p', long, group = "recommend_group")]
        file_path: Option<PathBuf>,

        /// The number of recommendations to retrieve
        #[arg(short, long, default_value_t = 10)]
        num: usize,

        /// The format of the output (json or m3u8)
        #[arg(short, long)]
        format: Option<String>,

        /// The output file path (required if format is specified)
        #[arg(short, long)]
        output: Option<PathBuf>,
    },
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    let filter = EnvFilter::new(
        "symphonia_format_ogg=off,symphonia_core=off,sea_orm_migration::migrator=off,info",
    );

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_test_writer()
        .init();

    // Determine the path from either the option or the positional argument
    let path = cli.library.or(cli.library0).expect("Path is required");

    let canonicalized_path = match canonicalize(&path) {
        Ok(path) => path,
        Err(e) => {
            eprintln!("Failed to canonicalize path: {}", e);
            return;
        }
    };

    let lib_path = match canonicalized_path.to_str() {
        Some(path) => path,
        None => {
            eprintln!("Invalid path, could not convert to string");
            return;
        }
    };

    let main_db = match connect_main_db(lib_path).await {
        Ok(db) => db,
        Err(e) => {
            eprintln!("Failed to connect to main database: {}", e);
            return;
        }
    };

    let analysis_db = match connect_recommendation_db(lib_path) {
        Ok(db) => db,
        Err(e) => {
            eprintln!("Failed to connect to analysis database: {}", e);
            return;
        }
    };

    match &cli.command {
        Commands::Scan => {
            scan_audio_library(&main_db, &path, true).await;
            println!("Library scanned successfully.");
        }
        Commands::Analyze => {
            if let Err(e) = analysis_audio_library(&main_db, &path, 10).await {
                eprintln!("Audio analysis failed: {}", e);
                return;
            }

            if let Err(e) = sync_recommendation(&main_db, &analysis_db).await {
                eprintln!("Sync recommendation failed: {}", e);
                return;
            }

            println!("Audio analysis completed successfully.");
        }
        Commands::Recommend {
            item_id,
            file_path,
            num,
            format,
            output,
        } => {
            let file_id = if let Some(item_id) = item_id {
                *item_id
            } else if let Some(file_path) = file_path {
                match get_file_id_from_path(&main_db, &path, file_path).await {
                    Ok(id) => id,
                    Err(e) => {
                        eprintln!("{}", e);
                        return;
                    }
                }
            } else {
                eprintln!("Either item_id or file_path must be provided.");
                return;
            };

            let recommendations = match get_recommendation(&analysis_db, file_id, *num) {
                Ok(recommendations) => recommendations,
                Err(e) => {
                    eprintln!("Failed to get recommendations: {}", e);
                    return;
                }
            };

            // Get file details of recommendations
            let ids: Vec<i32> = recommendations.iter().map(|(id, _)| *id as i32).collect();
            let files = match get_files_by_ids(&main_db, &ids).await {
                Ok(files) => files,
                Err(e) => {
                    eprintln!("Failed to get files by IDs: {}", e);
                    return;
                }
            };

            match format.as_deref() {
                Some("json") => {
                    let output_path = match output {
                        Some(path) => path,
                        None => {
                            eprintln!("Output file path is required when format is specified");
                            return;
                        }
                    };

                    // Check and correct file extension
                    let corrected_path = check_and_correct_extension(&canonicalized_path.join(output_path), "json");
                    if corrected_path != *output_path {
                        eprintln!("Warning: Output file extension corrected to .json");
                    }

                    // Create directories if they don't exist
                    if let Some(parent) = corrected_path.parent() {
                        if let Err(e) = fs::create_dir_all(parent) {
                            eprintln!("Failed to create directories: {}", e);
                            return;
                        }
                    }

                    let json_data = json!(recommendations);
                    let mut file = match File::create(&corrected_path) {
                        Ok(file) => file,
                        Err(e) => {
                            eprintln!("Failed to create file: {}", e);
                            return;
                        }
                    };

                    if let Err(e) = file.write_all(json_data.to_string().as_bytes()) {
                        eprintln!("Failed to write to file: {}", e);
                        return;
                    }

                    println!("Recommendations saved to JSON file.");
                }
                Some("m3u8") => {
                    let output_path = match output {
                        Some(path) => path,
                        None => {
                            eprintln!("Output file path is required when format is specified");
                            return;
                        }
                    };

                    // Check and correct file extension
                    let corrected_path = check_and_correct_extension(&canonicalized_path.join(output_path), "m3u8");
                    if corrected_path != *output_path {
                        eprintln!("Warning: Output file extension corrected to .m3u8");
                    }

                    // Create directories if they don't exist
                    if let Some(parent) = corrected_path.parent() {
                        if let Err(e) = fs::create_dir_all(parent) {
                            eprintln!("Failed to create directories: {}", e);
                            return;
                        }
                    }

                    let mut file = match File::create(&corrected_path) {
                        Ok(file) => file,
                        Err(e) => {
                            eprintln!("Failed to create file: {}", e);
                            return;
                        }
                    };

                    if let Err(e) = file.write_all("#EXTM3U\n".as_bytes()) {
                        eprintln!("Failed to write to file: {}", e);
                        return;
                    }

                    for file_info in files {
                        let relative_path =
                            path.join(&file_info.directory).join(&file_info.file_name);
                        let relative_to_output = match pathdiff::diff_paths(
                            &relative_path,
                            corrected_path.parent().unwrap(),
                        ) {
                            Some(path) => path,
                            None => {
                                eprintln!("Failed to calculate relative path");
                                return;
                            }
                        };

                        if let Err(e) = writeln!(file, "{}", relative_to_output.display()) {
                            eprintln!("Failed to write to file: {}", e);
                            return;
                        }
                    }

                    println!("Recommendations saved to M3U8 file: {}", corrected_path.to_str().unwrap());
                }
                Some(_) => {
                    eprintln!("Unsupported format. Supported formats are 'json' and 'm3u8'.");
                }
                None => {
                    // Create a table to display recommendations
                    let mut table = Table::new();
                    table.add_row(row!["ID", "Distance", "File Path"]);
                    table.set_format(*format::consts::FORMAT_NO_LINESEP_WITH_TITLE);

                    for (id, distance) in &recommendations {
                        let file_info = files.iter().find(|f| f.id == *id as i32);
                        if let Some(file_info) = file_info {
                            let file_path =
                                path.join(&file_info.directory).join(&file_info.file_name);
                            table.add_row(row![
                                format!("{:0>5}", id),
                                format!("{:.4}", distance),
                                file_path.display()
                            ]);
                        }
                    }

                    table.printstd();
                }
            }
        }
    }
}

fn check_and_correct_extension(path: &Path, expected_extension: &str) -> PathBuf {
    if path.extension().and_then(|ext| ext.to_str()) != Some(expected_extension) {
        let mut corrected_path = path.to_path_buf();
        corrected_path.set_extension(expected_extension);
        corrected_path
    } else {
        path.to_path_buf()
    }
}