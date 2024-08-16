package Cpanel::FileUtils;

# cpanel - Cpanel/FileUtils.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug            ();
use Cpanel::FileUtils::Path  ();
use Cpanel::FileUtils::Link  ();
use Cpanel::FileUtils::Equiv ();
use Cpanel::FileUtils::Lines ();

our $VERSION = '1.9';

sub writefile {
    require Cpanel::FileUtils::Write;
    goto \&Cpanel::FileUtils::Write::overwrite_no_exceptions;
}

sub safecopy {
    require Cpanel::FileUtils::Copy;
    goto \&Cpanel::FileUtils::Copy::safecopy;
}

sub touchfile {
    require Cpanel::FileUtils::TouchFile;
    goto \&Cpanel::FileUtils::TouchFile::touchfile;
}

sub safemv {
    require Cpanel::FileUtils::Move;
    goto \&Cpanel::FileUtils::Move::safemv;
}

*equivalent_files = *Cpanel::FileUtils::Equiv::equivalent_files;
*findinpath       = *Cpanel::FileUtils::Path::findinpath;
*cleanpath        = *Cpanel::FileUtils::Path::cleanpath;
*safeunlink       = *Cpanel::FileUtils::Link::safeunlink;
*_replicate_file  = *Cpanel::FileUtils::Link::_replicate_file;
*safelink         = *Cpanel::FileUtils::Link::safelink;
*get_file_lines   = *Cpanel::FileUtils::Lines::get_file_lines;
*get_last_lines   = *Cpanel::FileUtils::Lines::get_last_lines;
*has_txt_in_file  = *Cpanel::FileUtils::Lines::has_txt_in_file;
*appendline       = *Cpanel::FileUtils::Lines::appendline;

sub walk {
    my ( $rcount, $rdata ) = @_;
    my $begin = $$rcount;
    $$rcount = index( $$rdata, "\n", $begin + 1 );
    if ( $$rcount == -1 ) {
        return undef;
    }
    return substr( $$rdata, $begin, ( $$rcount - $begin ) );
}

sub regex_rep_file {
    my ( $file, $regex_ref, $error_hr ) = @_;

    require Cpanel::SafeFile;
    require Cpanel::StringFunc::Replace;

    # TODO: this needs to use transaction so its rename() into place safe
    my @new_contents;
    if ( !-e $file ) { Cpanel::FileUtils::TouchFile::touchfile($file); }
    my $filelock = Cpanel::SafeFile::safeopen( \*FH, '+<', $file );    # or return;
    if ( !$filelock ) {
        Cpanel::Debug::log_warn("Could not edit $file");
        return;
    }

    while ( my $line = readline FH ) {
        if ( $line !~ /^$/ && $line ne "\n" && $line ne "\r\n" ) {
            $line = Cpanel::StringFunc::Replace::regex_rep_str( $line, $regex_ref, $error_hr );
        }
        push @new_contents, $line;
    }

    return if ref $error_hr eq 'HASH' && keys %{$error_hr};

    seek( FH, 0, 0 );
    print FH @new_contents;
    truncate( FH, tell(FH) );
    return Cpanel::SafeFile::safeclose( \*FH, $filelock );    # or return ;
}

1;
