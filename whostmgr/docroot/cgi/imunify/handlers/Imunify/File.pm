package Imunify::File;

use strict;
use warnings FATAL => 'all';
use File::Copy;
use File::Basename;
use Fcntl qw(SEEK_SET);
use Encode;
use Imunify::Exception;


# default 100 KB
use constant READ_LENGTH => 1024 * 100;

sub get {
    my ($file) = @_;
    die Imunify::Exception->new("File not found.") if !-e $file;
    open FH, '<:encoding(UTF-8)', $file || die Imunify::Exception->new("Unable to open file.");

    return do {
        local $/;
        <FH>;
    };
}

1;