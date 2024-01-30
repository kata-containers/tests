//
// Copyright (c) 2023 Maxwell Wendlandt, Christopher Robinson
//
// SPDX-License-Identifier: Apache-2.0
//
mod node;
mod output;
mod stats;
mod toc;
mod validate;

use output::generate_output;
use stats::print_document_statistics;
use toc::collect_heading_info;
use validate::{validate_document_structure, validate_links};

use comrak::{
    parse_document, Arena, ComrakOptions,
};
use std::env;
use std::fs;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();

    let arena = Arena::new();

    if args.len() < 2 {
        return Err("Usage: <input_file>".into());
    }

    let input_file_path = env::current_dir()?.join(args[1].clone());

    let input = fs::read_to_string(&input_file_path)?;

    let root = parse_document(&arena, &input, &ComrakOptions::default());

    let heading_infos = collect_heading_info(&root);

    let toc = toc::generate_toc(&heading_infos);

    let link_validation_result = validate_links(&root, &input);
    let structure_validation_result = validate_document_structure(&root, &input_file_path);

    let document_statistics = print_document_statistics(&root);

    generate_output(
        &input_file_path,
        &toc,
        &link_validation_result,
        &structure_validation_result,
        &document_statistics,
        &heading_infos[..],
    );

    Ok(())
}