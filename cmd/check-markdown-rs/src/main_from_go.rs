use std::path::PathBuf;
use std::error::Error;
use clap::{Arg, App, AppSettings, SubCommand, ArgMatches};

#[macro_use]
extern crate log;

mod common;
mod display_handlers;
mod doc;
mod heading;
mod intra_doc_links;
mod link;
mod list;
mod markdown;
mod referenced;
mod toc;

use crate::common::{DataToShow, handle_doc, handle_intra_doc_links, handle_logging};
use crate::display_handlers::DisplayHandlers;
use crate::doc::new_doc;

fn common_list_handler(matches: &ArgMatches, what: DataToShow) -> Result<(), Box<dyn Error>> {
    handle_logging(matches);

    let handlers = DisplayHandlers::new(matches.value_of("separator").unwrap(), matches.is_present("no-header"))?;

    let format = matches.value_of("format").unwrap();
    if format == "help" {
        let available_formats = handlers.get();

        for format in available_formats {
            println!("{}", format);
        }

        return Ok(())
    }

    let handler = handlers.find(format).ok_or_else(|| format!("no handler for format '{}'", format))?;

    let files: Vec<&str> = matches.values_of("FILES").unwrap().collect();

    for file in files {
        let doc = new_doc(file, logger);

        let mut referenced = vec![doc];
        let mut index = 0;
        while index < referenced.len() {
            let current_doc = referenced[index];
            if !current_doc.parsed {
                current_doc.parse(strict)?;

                let refs = current_doc.referenced_docs(&doc_root)?;
                referenced.extend(refs);
            }
            index += 1;
        }

        handle_intra_doc_links(&mut referenced)?;

        match what {
            DataToShow::ShowHeadings => {
                list::display_headings(&referenced, handler)?;
            },
            DataToShow::ShowLinks => {
                list::display_links(&referenced, handler)?;
            }
        }
    }

    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let matches = App::new(env!("CARGO_PKG_NAME"))
        .version(env!("CARGO_PKG_VERSION"))
        .setting(AppSettings::SubcommandRequired)
        .about("Tool to check GitHub-Flavoured Markdown (GFM) format documents")
        .arg(Arg::with_name("debug")
            .short("d")
            .long("debug")
            .help("Display debug information")
        )
        .arg(Arg::with_name("doc-root")
            .short("r")
            .long("doc-root")
            .value_name("DOC_ROOT")
            .help("Specify document root")
            .default_value(".")
            .takes_value(true)
        )
        .arg(Arg::with_name("single-doc-only")
            .short("o")
            .long("single-doc-only")
            .help("Only check primary (specified) document")
        )
        .arg(Arg::with_name("strict")
            .short("s")
            .long("strict")
            .help("Enable strict mode")
        )
        .subcommand(
            SubCommand::with_name("check")
                .about("Perform tests on the specified document")
                .display_order(0)
                .arg(
                    Arg::with_name("FILES")
                        .help("Sets the input file(s) to use")
                        .required(true)
                        .multiple(true)
                        .min_values(1)
                )
                .action(|matches: &ArgMatches| {
                    handle_doc(matches, false)
                })
        )
        .subcommand(
            SubCommand::with_name("toc")
                .about("Display a markdown Table of Contents")
                .display_order(1)
                .arg(
                    Arg::with_name("FILES")
                        .help("Sets the input file(s) to use")
                        .required(true)
                        .multiple(true)
                        .min_values(1)
                )
                .action(|matches: &ArgMatches| {
                    handle_doc(matches, true)
                })
        )
        .subcommand(
            SubCommand::with_name("list")
                .about("Display particular parts of the document")
                .display_order(2)
                .subcommand(
                    SubCommand::with_name("headings")
                        .about("Display headings")
                        .arg(
                            Arg::with_name("format")
                                .short("f")
                                .long("format")
                                .value_name("FORMAT")
                                .help("Display in specified format ('help' to show all)")
                                .default_value("text")
                                .takes_value(true)
                        )
                        .arg(
                            Arg::with_name("no-header")
                                .long("no-header")
                                .help("Disable display of header (if format supports one)")
                        )
                        .arg(
                            Arg::with_name("separator")
                                .long("separator")
                                .value_name("SEPARATOR")
                                .help("Use the specified separator character (TSV format only)")
                                .default_value("\t")
                                .takes_value(true)
                        )
                        .arg(
                            Arg::with_name("FILES")
                                .help("Sets the input file(s) to use")
                                .required(true)
                                .multiple(true)
                                .min_values(1)
                        )
                        .action(|matches: &ArgMatches| {
                            common_list_handler(matches, DataToShow::ShowHeadings)
                        })
                )
                .subcommand(
                    SubCommand::with_name("links")
                        .about("Display links")
                        .arg(
                            Arg::with_name("format")
                                .short("f")                               
                                .long("format")
                                .value_name("FORMAT")
                                .help("Display in specified format ('help' to show all)")
                                .default_value("text")
                                .takes_value(true)
                        )
                        .arg(
                            Arg::with_name("no-header")
                                .long("no-header")
                                .help("Disable display of header (if format supports one)")
                        )
                        .arg(
                            Arg::with_name("separator")
                                .long("separator")
                                .value_name("SEPARATOR")
                                .help("Use the specified separator character (TSV format only)")
                                .default_value("\t")
                                .takes_value(true)
                        )
                        .arg(
                            Arg::with_name("FILES")
                                .help("Sets the input file(s) to use")
                                .required(true)
                                .multiple(true)
                                .min_values(1)
                        )
                        .action(|matches: &ArgMatches| {
                            common_list_handler(matches, DataToShow::ShowLinks)
                        })
                )
        )
        .get_matches();

    let doc_root = PathBuf::from(matches.value_of("doc-root").unwrap());

    let strict = matches.is_present("strict");

    let single_doc_only = matches.is_present("single-doc-only");

    let subcommand_matches = matches.subcommand_matches(matches.subcommand_name().unwrap()).unwrap();

    match subcommand_matches.name {
        "check" => {
            handle_doc(subcommand_matches, false)?;
        },
        "toc" => {
            handle_doc(subcommand_matches, true)?;
        },
        "list" => {
            let subcommand_matches = subcommand_matches.subcommand_matches(subcommand_matches.subcommand_name().unwrap()).unwrap();
            let what = if subcommand_matches.name == "headings" {
                DataToShow::ShowHeadings
            } else {
                DataToShow::ShowLinks
            };
            common_list_handler(subcommand_matches, what)?;
        },
        _ => unreachable!(),
    }

    Ok(())
}

