<?php
// Copyright 1999-2020. Plesk International GmbH. All rights reserved.

// @todo simplify & fix this crutch

if ($key = array_search('--stdin-env', $argv) !== false) {
    $data = fgets(STDIN,getenv('WORDPRESS_STDIN_LENGTH') + 1);
    $argsContent = (array) json_decode($data,true);

    $args = $assoc_args = [];
    $args[] = __FILE__;
    foreach ($argsContent as $name => $value) {
        if ($name === 'WORDPRESS_PROXY_COMMAND_ARGS') {
            $args = array_merge($args, $value);
        } elseif ($name === 'WORDPRESS_PROXY_COMMAND_ASSOC_ARGS') {
            $assoc_args = $value;
        } else if (is_string($value) && getenv($name) === false) {
            putenv("$name=$value");
        }
    }

    foreach ($assoc_args as $k => $v) {
        $args[] = "--{$k}={$v}";
    }
    $_SERVER['argv'] = $argv = $args;
}

$_SERVER['PHP_SELF'] = $_SERVER['SCRIPT_NAME'] = $_SERVER['SCRIPT_FILENAME'] = $_SERVER['PATH_TRANSLATED'] =
    $_SERVER['argv'][0] = $argv[0] = __DIR__ . '/vendor/wp-cli/wp-cli/php/boot-fs.php';

require_once __DIR__ . '/vendor/wp-cli/wp-cli/php/boot-fs.php';
