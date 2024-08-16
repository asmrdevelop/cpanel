package Cpanel::Rand;

# cpanel - Cpanel/Rand.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();
use Cpanel::Hash             ();
use Cpanel::SV               ();

my $MAX_TMPFILE_CREATE_ATTEMPTS = 50;

use constant WRONLY_CREAT_EXCL => $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL;

our ( $DO_OPEN, $SKIP_OPEN, $TYPE_FILE, $TYPE_DIR ) = ( 0, 1, 0, 1 );

sub getranddata {
    require Cpanel::Rand::Get;
    goto \&Cpanel::Rand::Get::getranddata;
}

sub gettmpfile {
    return get_tmp_file_by_name('/tmp/cpanel.TMP');
}

sub gettmpdir {
    return get_tmp_dir_by_name('/tmp/cpanel.TMP');
}

sub api2_getranddata {
    my %CFG = @_;
    require Cpanel::Rand::Get;
    return { 'random' => Cpanel::Rand::Get::getranddata( $CFG{'length'} || 16 ) };
}

our %API = (
    getranddata => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub get_tmp_dir_by_name {
    my $templatefile = shift;
    my $suffix       = shift || '.work';
    return get_tmp_file_by_name( $templatefile, $suffix, $TYPE_DIR, $DO_OPEN );
}

sub get_tmp_file_by_name {
    my $templatefile = shift;
    my $suffix       = shift || '.work';
    my $type         = shift || $TYPE_FILE;
    my $open         = shift || $DO_OPEN;
    if ( index( $suffix, '.' ) != 0 ) {
        substr( $suffix, 0, 0, '.' );
    }
    my $last_error;
    my $fh;
    my $randlength = 8;
    my $maxlength  = 255 - $randlength - 1;
    my $root       = $templatefile . $suffix;
    my (@path)     = split( m{/+}, $root );
    my $file       = substr( pop @path, -$maxlength, $maxlength );
    my $tmpfile    = join( '/', @path, $file ) . '.' . _rand_trailer($randlength);
    Cpanel::SV::untaint($tmpfile);

    local $!;
    my $attempts = 0;
    {
        my $old = umask(0);    # Cpanel::Umask was too slow here when creating many zone file
        while (
            ++$attempts < $MAX_TMPFILE_CREATE_ATTEMPTS
            && (
                ( $open != $DO_OPEN && -e $tmpfile )
                || (
                    $open == $DO_OPEN
                    ? (
                        $type == $TYPE_DIR
                        ? !mkdir( $tmpfile, 0700 )
                        : !sysopen( $fh, $tmpfile, WRONLY_CREAT_EXCL, 0600 )
                    )
                    : 0
                )
            )
        ) {
            $last_error = $!;
            my (@path)  = split( m{/+}, $root );
            my $file    = substr( pop @path, -$maxlength, $maxlength );
            my $tmpfile = join( '/', @path, $file ) . '.' . _rand_trailer($randlength);
            Cpanel::SV::untaint($tmpfile);
        }
        umask($old);
    }

    if ( $attempts == $MAX_TMPFILE_CREATE_ATTEMPTS ) {
        die Cpanel::Exception::create( 'TempFileCreateError', [ path => $tmpfile, error => $last_error ] );
    }

    return ( $tmpfile, $fh ) if wantarray && $type == $TYPE_FILE;
    return $tmpfile;    # file will close when $fh leaves context
}

sub _rand_trailer {
    return substr( sprintf( '%08x', Cpanel::Hash::get_fastest_hash( join( '-', substr( rand, 2 ), $$, time ) ) ), 0, $_[0] );
}

1;
