package Cpanel::LoginProfile;

# cpanel - Cpanel/LoginProfile.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug    ();
use Cpanel::LoadFile ();
use Cpanel::SafeFile ();

my @LOGIN_FILES = ( '/etc/bashrc', '/etc/profile' );
my $profile_dir = '/usr/local/cpanel/etc/login_profile';

sub _get_profile_comment_line {
    my $key = shift;
    $key =~ s/\///g;
    my $line = '';

    my $file = $profile_dir . '/' . $key . '.sh';

    if ( open( my $profile_script_fh, '<', $file ) ) {
        while ( readline($profile_script_fh) ) {
            if (/^\s*#([^-]+)--\s*/) {
                $line = $1;
                last;
            }
        }
    }
    else {
        return ( 0, "Could not open $file: $!" );
    }
    $line =~ s/\s+$//g;
    return $line ? ( 1, "Retrieved comment line from $file", $line ) : ( 0, "Failed to retrieve comment line from $file" );
}

sub profile_is_installed {
    my $key = shift;
    $key =~ s/\///g;

    my ( $status, $msg, $comment_line ) = _get_profile_comment_line($key);
    return ( 0, "Unknown profile $key: $msg" ) if !$comment_line;

    my $begin_regex = qr/^\s*#\s*\Q$comment_line\E\s*--\s*BEGIN/m;

    return Cpanel::LoadFile::loadfile('/etc/profile') =~ $begin_regex ? 1 : 0;
}

sub install_profile {
    my $key = shift;
    $key =~ s/\///g;

    my ( $status, $msg, $comment_line ) = _get_profile_comment_line($key);
    return ( 0, "Unknown profile $key: $msg" ) if !$comment_line;

    remove_profile($key);    # remove duplicates JIC

    if ( -d '/etc/profile.d' ) {
        foreach my $ext ( 'sh', 'csh' ) { system( "cp", "-f", "$profile_dir/$key.$ext", "/etc/profile.d/$key.$ext" ) if -f "$profile_dir/$key.$ext"; }
    }

    my $script_to_insert = Cpanel::LoadFile::loadfile("$profile_dir/$key.sh");
    $script_to_insert .= "\n" if $script_to_insert !~ /\n$/g;

    foreach my $login_file (@LOGIN_FILES) {
        my ( $login_lock, $login_file_fh );
        if ( !-e $login_file ) {
            $login_lock = Cpanel::SafeFile::safeopen( $login_file_fh, '>', $login_file )
              or return ( 0, "Unable to open '$login_file' due to an error: $!" );
            print {$login_file_fh} $script_to_insert;
        }
        else {
            $login_lock = Cpanel::SafeFile::safeopen( $login_file_fh, '+<', $login_file )
              or return ( 0, "Unable to open '$login_file' due to an error: $!" );
            local $/;
            my $contents = readline($login_file_fh);
            print {$login_file_fh} ( ( $contents =~ /\n$/ ? '' : "\n" ) . $script_to_insert );
        }
        Cpanel::SafeFile::safeclose( $login_file_fh, $login_lock );
    }

    return ( 1, "Profile $key installed" );
}

sub remove_profile {
    my $key = shift;
    $key =~ s/\///g;

    my ( $status, $msg, $comment_line ) = _get_profile_comment_line($key);
    return ( 0, "Unknown profile $key: $msg" ) if !$comment_line;

    unlink( "/etc/profile.d/$key.sh", "/etc/profile.d/$key.csh" ) if ( -d '/etc/profile.d' );

    my $begin_regex = qr/^\s*#\s*\Q$comment_line\E\s*--\s*BEGIN/;
    my $end_regex   = qr/^\s*#\s*\Q$comment_line\E\s*--\s*END/;

    foreach my $login_file (@LOGIN_FILES) {

        if ( !-e $login_file ) {
            next;
        }

        my $login_lock = Cpanel::SafeFile::safeopen( my $login_file_fh, '+<', $login_file );
        if ( !$login_lock ) {
            Cpanel::Debug::log_warn("Failed to open and lock “$login_file”: $!");
            next;
        }

        my @CONTENTS = <$login_file_fh>;
        seek( $login_file_fh, 0, 0 );
        my $in_code = 0;
        foreach my $line (@CONTENTS) {
            if ( $line =~ $begin_regex ) {
                $in_code = 1;
            }
            elsif ( $line =~ $end_regex ) {
                $in_code = 0;
            }
            elsif ( !$in_code ) {
                print {$login_file_fh} $line;
            }
        }
        truncate( $login_file_fh, tell($login_file_fh) );
        Cpanel::SafeFile::safeclose( $login_file_fh, $login_lock );
    }
    return ( 1, "Profile $key removed" );
}

1;
