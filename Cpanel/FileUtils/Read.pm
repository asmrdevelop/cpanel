package Cpanel::FileUtils::Read;

# cpanel - Cpanel/FileUtils/Read.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Read - error-checked filesystem read utilities

=head1 SYNOPSIS

    use Cpanel::FileUtils::Read;

    Cpanel::FileUtils::Read::for_each_line(
        '/path/to/file',
        sub {
            my $iter = shift;

            my $current_line = $_;

            my $line_index = $iter->get_iteration_index();
            my $bytes_read = $iter->get_bytes_read();

            $iter->stop();
        },
    );

    Cpanel::FileUtils::Read::for_each_directory_node(
        '/path/to/directory',
        sub {
            my $iter = shift;

            my $current_node = $_;

            my $dir_index = $iter->get_iteration_index();

            $iter->stop();
        },
    );

=head1 DESCRIPTION

This module attempts to provide a clean interface for completely error-checked
filesystem reads. This will save a lot of boilerplate, the tradeoff being that
the number of coderefs this uses makes it slow on large files/directories.

See L<Cpanel::StringFunc::LineIterator> for similar functionality with an
in-memory buffer.

=cut

use Errno ();
use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

#NOTE: These methods incur a performance penalty for each iteration
#versus a simple loop. The advantage is the built-in error checking
#and reduced boilerplate.
#
#$todo_cr gets passed to the relevant IteratorBase subclass instance.

sub for_each_line {
    my ( $path, $todo_cr ) = @_;

    return _for_each_thingie(
        path          => $path,
        todo_cr       => $todo_cr,
        whatsit       => 'File',
        iterator_type => 'Line',
        do_open       => sub { open( my $fh, '<', $path ) or return; $fh },
        do_close      => sub { close shift },
    );
}

sub for_each_directory_node ( $path, $todo_cr ) {
    return _for_each_directory_node( $path, $todo_cr, 0 );
}

sub for_each_directory_node_if_exists ( $path, $todo_cr ) {
    return _for_each_directory_node( $path, $todo_cr, 1 );
}

sub _for_each_directory_node ( $path, $todo_cr, $ignore_enoent_yn ) {    ## no critic qw(ManyArgs) - mis-parse
    return _for_each_thingie(
        path          => $path,
        todo_cr       => $todo_cr,
        whatsit       => 'Directory',
        iterator_type => 'DirectoryNode',
        do_open       => sub { opendir( my $fh, $path ) or return; $fh },
        do_close      => sub { closedir shift },
        ignore_enoent => $ignore_enoent_yn,
    );
}

sub _for_each_thingie {
    my %opts = @_;

    my $iterator_class = "Cpanel::FileUtils::Read::$opts{'iterator_type'}Iterator";

    Cpanel::LoadModule::load_perl_module($iterator_class);

    local $!;

    my $fh = $opts{'do_open'}->() or do {
        if ( $! == Errno::ENOENT && $opts{'ignore_enoent'} ) {
            return 0;
        }

        if ( $opts{'whatsit'} eq 'Directory' ) {
            die Cpanel::Exception::create( "IO::DirectoryOpenError", [ path => $opts{'path'}, error => $! ] );
        }
        die Cpanel::Exception::create( "IO::FileOpenError", [ path => $opts{'path'}, error => $! ] );
    };

    try {
        $iterator_class->new( $fh, $opts{'todo_cr'} );
    }
    catch {
        if ( UNIVERSAL::isa( $_, "Cpanel::Exception::IO::$opts{'whatsit'}ReadError" ) ) {
            if ( $opts{'whatsit'} eq 'Directory' ) {
                die Cpanel::Exception::create( "IO::DirectoryReadError", [ error => $_->get('error'), path => $opts{'path'} ] );
            }
            die Cpanel::Exception::create( "IO::FileReadError", [ error => $_->get('error'), path => $opts{'path'} ] );
        }

        die $_;
    };

    $opts{'do_close'}->($fh) or do {
        if ( $opts{'whatsit'} eq 'Directory' ) {
            die Cpanel::Exception::create( "IO::DirectoryCloseError", [ path => $opts{'path'}, error => $! ] );
        }
        die Cpanel::Exception::create( "IO::FileCloseError", [ path => $opts{'path'}, error => $! ] );
    };

    return 1;
}

1;
