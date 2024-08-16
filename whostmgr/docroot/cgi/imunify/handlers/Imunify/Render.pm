package Imunify::Render;

use strict;
use warnings FATAL => 'all';

use Cpanel::JSON;
use Imunify::File;
use Imunify::Utils;
use Imunify::Config;
use Whostmgr::HTMLInterface ();

use constant MODE => 'prod';

use constant  {
    HTTP_STATUS_OK => 200,
    HTTP_STATUS_INTERNAL_ERROR => 500,
    HTTP_STATUS_BAD_GATEWAY => 502
};

#use CGI::Carp qw(fatalsToBrowser); # uncomment to debug 500 error

my %HTTP_STATUS = (
    &HTTP_STATUS_OK => 'HTTP/1.1 200 OK',
    &HTTP_STATUS_INTERNAL_ERROR => 'HTTP/1.1 500 Internal Server Error',
    &HTTP_STATUS_BAD_GATEWAY => 'HTTP/1.1 502 Bad Gateway'
);

sub JSONHeader {
    my ($status, $command) = @_;
    $command = '' if !defined $command;
    $command =~ s/[^[:alnum:][:punct:] ]+?/ /g;
    $status = HTTP_STATUS_OK if !defined $status || !defined $HTTP_STATUS{$status};

    print "X-I360-COMMAND: $command\n" if MODE ne 'prod';
    print $HTTP_STATUS{$status}, "\n";
    print "Content-type: application/json; charset=utf-8\n\n";
}

sub JSON {
    my ($data, $command, $warnings) = @_;
    my %result = (
        'result' => 'success',
        'data' => $data
    );

    if ($warnings) {
        %result = (
            'result' => 'warnings',
            'messages' => $warnings,
            'data' => $data,
        );
    }

    JSONHeader(HTTP_STATUS_OK, $command);
    print Cpanel::JSON::SafeDump(\%result);
    exit 0;
}

sub escapeParams {
    my ($value) = @_;
    $value =~ s/'/'\\''/g;
    $value = "'".$value."'";
    return $value;
}

1;
