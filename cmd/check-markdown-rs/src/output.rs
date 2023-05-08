//
// Copyright (c) 2023 Maxwell Wendlandt, Christopher Robinson
//
// SPDX-License-Identifier: Apache-2.0
//
use std::collections::HashMap;
use std::path::{PathBuf};

pub fn generate_output(
    input_file: &PathBuf,
    toc: &str,
    link_validation_result: &Result<(), Vec<String>>,
    structure_validation_result: &Result<(), Vec<super::validate::StructureError>>,
    document_statistics: &HashMap<&str, usize>,
    heading_infos: &[super::toc::HeadingInfo],
) {
    println!("Final Output for file {:?}:", input_file);

    println!("\nDocument Structure Validation:");
    match structure_validation_result {
        Ok(_) => println!("  The document structure is valid."),
        Err(errors) => {
            println!("  Found {} file(s) with structure errors:", errors.len());
            for error in errors {
                if let Some(heading) = &error.heading {
                    eprintln!("  File: {:?}, Error: {}", error.file, error.error);
                } else {
                    eprintln!("  File: {:?}, Error: {}", error.file, error.error);
                }
            }
        }
    }

    println!("    Level 1 Headings:");
    for heading_info in heading_infos {
        if heading_info.level == 1 {
            println!("    - [{}](#{})", heading_info.text, heading_info.id,);
        }
    }

    println!("\nTable of Contents:");
    println!("{}", toc);

    println!("\nLink Validation:");
    match link_validation_result {
        Ok(_) => println!("  All links are valid."),
        Err(errors) => {
            println!(
                "  Found {} file(s) with link validation errors:",
                errors.len()
            );
            for error in errors {
                eprintln!("  Error: {}", error);
            }
        }
    }

    println!("\nDocument Statistics:");
    for (stat, count) in document_statistics {
        println!("  {}: {}", stat, count);
    }
}

