# CLI for df_translation_library

Run commands from the cli directory.

Print contents of a mo file:

```shell
zig build run -- print_mo --path ../test_data/test.mo
```

Output example:

```txt
print_mo
path=../test_data/test.mo
number of strings: 5
original string table offset: 28
translation string table offset: 68

context: NULL
original: 
translation: Some po header info

context: Context
original: Text 4
translation: Translation 4

context: NULL
original: Text 1
translation: Translation 1

context: NULL
original: Text 2
translation: Translation 2

context: NULL
original: Text 3
translation: Translation 3
```
