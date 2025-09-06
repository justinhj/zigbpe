# ZigBPE

A simple implementation of the Byte Pair Encoding (BPE) algorithm in Zig.

## What is BPE?

Byte Pair Encoding is a data compression technique that iteratively replaces the most frequent pair of bytes in a sequence with a single, unused byte. This project uses the same principle to tokenize text for Natural Language Processing tasks.

## Implementation

The core of the implementation is in `code/zigbpe.zig`. It reads a text file, and then iteratively merges the most frequent pair of tokens into a new token.

A key data structure is the `SkippingList`, found in `code/skipping_list.zig`. This is a custom data structure that allows for efficient merging of tokens. When a pair of tokens is merged, the second token in the pair is not removed from the list, but instead marked as "skipped". This is done by using the high bits of the token to store a "skip" value. This avoids costly memory reallocations and makes the merging process very fast.

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
