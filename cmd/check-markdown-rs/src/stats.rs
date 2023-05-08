use comrak::arena_tree::Node;                                                                                                                                      
 use comrak::{                                                                                                                                                      
     nodes::{Ast, NodeValue},                                                                                                                                       
 };                                                                                                                                                                 
 use std::cell::RefCell;                                                                                                                                            
 use std::collections::HashMap;   

// Function to gather and print document statistics
pub fn print_document_statistics<'a>(root: &'a Node<'a, RefCell<Ast>>) -> HashMap<&'a str, usize> {
    let mut statistics: HashMap<&str, usize> = HashMap::new();
    gather_document_statistics(root, &mut statistics);

    statistics
}

// Recursive function to gather document statistics
pub fn gather_document_statistics<'a>(
    node: &'a Node<'a, RefCell<Ast>>,
    statistics: &mut HashMap<&'a str, usize>,
) {
    match &node.data.borrow().value {
        NodeValue::Heading(_) => {
            *statistics.entry("headings").or_insert(0) += 1;
        }
        NodeValue::Text(text) => {
            let word_count = String::from_utf8_lossy(text.as_bytes())
                .split_whitespace()
                .count();
            *statistics.entry("words").or_insert(0) += word_count;
        }
        NodeValue::Link(_) => {
            *statistics.entry("links").or_insert(0) += 1;
        }
        _ => {}
    }

    for child in node.children() {
        gather_document_statistics(&child, statistics);
    }
}