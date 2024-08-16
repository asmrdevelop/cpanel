<?php
// Copyright 1999-2021. Plesk International GmbH. All rights reserved.
// Simple PHP utility to find & cut DEFINER statements from SQL dump files,
// writing result to another file.
// Usage: cut-definer.php <source-filename> <target-filename>

if ($argc != 3) {
    echo "Invalid arguments. Usage: cut-definer.php <source-filename> <target-filename>" . PHP_EOL;
    exit(1);
}

$sourceFilename = $argv[1];
$targetFilename = $argv[2];

$changesCount = 0;

$sourceFp = fopen($sourceFilename, "rb");
if ($sourceFp === false) {
    echo "Failed to open source file" . PHP_EOL;
    exit(1);
}

$targetFp = fopen($targetFilename, "wb");
if ($targetFp === false) {
    echo "Failed to open target file" . PHP_EOL;
    exit(1);
}

// We expect that line with DEFINER statement is less than 100KB
$blockLength = 1024 * 100;

$previousBlock = '';
$currentBlock = '';
$bothBlocks = '';
$pattern = '#\n/\*.*DEFINER=.*\*/;*\n#';

while (!feof($sourceFp)) {
    $currentBlock = fread($sourceFp, $blockLength);

    if ($currentBlock === false) {
        echo "Failed to read data" . PHP_EOL;
        exit(1);
    }

    $bothBlocks = $previousBlock . $currentBlock;
    $dumped = false;
    while (true) {
        $matched = preg_match($pattern, $bothBlocks, $matches, PREG_OFFSET_CAPTURE);
        if (!$matched) {
            break;
        }

        $startOffset = $matches[0][1];
        $length = strlen($matches[0][0]);

        $changesCount++;
        $result = fwrite($targetFp, substr($bothBlocks, 0, $startOffset));
        if ($result === false) {
            echo "Failed to write data" . PHP_EOL;
            exit(1);
        }
        $result = fwrite($targetFp, "\n");
        if ($result === false) {
            echo "Failed to write data" . PHP_EOL;
            exit(1);
        }
        $bothBlocks = substr($bothBlocks, $startOffset + $length);
        $dumped = true;
    }
    if (!$dumped) {
        if (strlen($previousBlock) > 0) {
            $result = fwrite($targetFp, $previousBlock);
            if ($result === false) {
                echo "Failed to write data" . PHP_EOL;
                exit(1);
            }
        }
        $bothBlocks = $currentBlock;
    }

    $previousBlock = $bothBlocks;
}

if (strlen($previousBlock) > 0) {
    $previousBlock = preg_replace($pattern, "\n", $previousBlock);
    $result = fwrite($targetFp, $previousBlock);
    if ($result === false) {
        echo "Failed to write data" . PHP_EOL;
        exit(1);
    }
}

$result = fclose($sourceFp);
if ($result === false) {
    echo "Failed to close target file" . PHP_EOL;
    exit(1);
}

echo $changesCount . PHP_EOL;
