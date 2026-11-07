# CLI for df_translation_library

Run commands from the cli directory.

## translate_raw

Translate one RAW file with a CSV dictionary. The CSV columns are `original`, `context`, and `translation`; the first row is data, not a header. Leave the context column empty for a context-free dictionary entry.

```shell
zig build run -- translate_raw --raw path/to/input.txt --dictionary path/to/dictionary.csv --output path/to/output.txt
```
