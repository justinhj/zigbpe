# ZigBPE

A simple implementation of the Byte Pair Encoding (BPE) algorithm in Zig.

## What is BPE?

Byte Pair Encoding is a data compression technique that iteratively replaces the most frequent pair of bytes in a sequence with a single, unused byte. This project uses the same principle to tokenize text for Natural Language Processing tasks.

## Implementation

The core of the implementation is in `code/zigbpe.zig`. It reads a text file, and then iteratively merges the most frequent pair of tokens into a new token.

## Assumptions

There are two distinct starting points to consider when implementing tokenization training. Firstly you can train on the entire data set as a single block of text; this is the approach used in Karpathy's initial implementation in [minbpe](https://github.com/karpathy/minbpe) which is for pedagogical purposes. See `basic.py`. This is the method used by SentencePiece, but not by most GPT family tokenizers.

The second method is train on the split text, based on pre-processing using a regular expression.

As such optimizing a trainer depends on which of these methods is used as the charactistics of the resulting workload is very different.

## Building and Running

To build the project, you need to have the Zig compiler installed. Then, you can run the following command:

```bash
zig build
```

This will create an executable in `zig-out/bin/zigbpe`.

To run the tokenizer on a text file, use the following command:

```bash
zig build run -- <path_to_file>
```

For example:

```bash
zig build run -- data/sample.txt
```

This will run the BPE algorithm on the `data/sample.txt` file and print the most frequent pairs at each step.

## Testing

To run the tests, use the following command:

```bash
zig test code/skipping_list.zig
```
