# Markdown Parser

This is a simple Markdown parser that reads a Markdown file, processes it, and outputs some useful information about the document. The parser uses the comrak library to parse the Markdown file into an abstract syntax tree (AST).

## Features

- Parses Markdown files and generates an abstract syntax tree (AST)
- Generates a table of contents (TOC) for the document
- Validates the structure of the document (e.g., correct heading level order)
- Validates internal and external links in the document
- Provides document statistics (e.g., number of headings, words, and links)

## Usage

```
$ cargo install --path .
$ check-markdown-rs input_file.md
```

To use the Markdown parser, compile the code and run the resulting binary with the input Markdown file as an argument:

<!-- Insert plaintext command to build and run the binary here -->

## Dependencies

The following dependencies are required for this project:

- comrak: A Rust implementation of the CommonMark spec for parsing Markdown
- url: A Rust library for URL manipulation
- std: The Rust standard library

To add these dependencies to your project, add the following lines to your Cargo.toml:

```
comrak = "0.18"
clap = "3.0"
url = "2.3.1"
```

## Code Overview


The main function of the code is `main()`, which reads the input file, parses it, and calls various functions to process the AST and generate output.

The code includes several utility functions:

- `print_nodes()`: Prints the AST nodes recursively
- `get_node_text()`: Gets the text content of a node
- `validate_document_structure()`: Validates the structure of the document
- `find_heading_nodes()`: Finds all heading nodes in the AST
- `generate_toc()`: Generates a table of contents based on the headings in the document
- `validate_links()`: Validates internal and external links in the document
- `find_heading_ids()`: Finds all heading IDs in the AST
- `find_link_nodes()`: Finds all link nodes in the AST
- `print_document_statistics()`: Gathers and prints document statistics
- `gather_document_statistics()`: Gathers document statistics recursively
- `generate_output()`: Generates the final output