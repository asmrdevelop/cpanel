package Cpanel::Mailman;

# cpanel - Cpanel/Mailman.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadCpConf   ();
use Cpanel::Mailman::Filesys     ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::SafeDir::MK          ();

*MAILMAN_DIR = \&Cpanel::Mailman::Filesys::MAILMAN_DIR;

#FYI: subscribe_policy "magic number" settings:
#1: Anyone can subscribe, w/ confirmation email
#2: Admin must approve request, NO confirmation email
#3: Admin must approve request, w/ confirmation email

#NOTE: Keep this in sync with UI code, e.g., the cPanel mailing lists page.
our %OPTS_TO_SET_A_LIST_AS_PRIVATE = qw(
  advertised          0
  archive_private     1
  subscribe_policy    3
);

#NOTE: This is not an exhaustive list by any stretch!
my %valid_cfg_parameters = (
    advertised       => [ 0, 1 ],
    archive_private  => [ 0, 1 ],
    subscribe_policy => [ 1, 2, 3 ],
);

sub have_lists {
    my $has_lists;

    if ( opendir( my $list_dir, MAILMAN_DIR() . '/lists' ) ) {
        while ( my $node = readdir $list_dir ) {
            if ( $node !~ /^\.|^mailman$/ ) {

                $has_lists = 1;
                last;
            }
        }

        closedir $list_dir or warn $!;
    }

    return $has_lists;
}

sub find_invalid_cfg_parameters {
    my ($cfg_hr) = @_;

    keys %$cfg_hr;    #reset the hash pointer

    my %invalid;

    while ( my ( $key, $val ) = each %$cfg_hr ) {
        next if !exists $valid_cfg_parameters{$key};

        my $validity = $valid_cfg_parameters{$key};
        if ( ref $validity eq 'ARRAY' ) {
            if ( !grep { $_ eq $val } @$validity ) {
                $invalid{$key} = [@$validity];
            }
        }
        else {
            die "Unknown validity type: " . ref($validity);
        }
    }

    return \%invalid;
}

sub skipmailman {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    return $cpconf->{'skipmailman'} || !have_lists();
}

sub setup_jail_flags {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    if ( $cpconf->{'skipmailman'} ) {
        unlink('/var/cpanel/conf/jail/flags/mount_usr_local_cpanel_3rdparty_mailman_suid');
    }
    else {
        Cpanel::SafeDir::MK::safemkdir( '/var/cpanel/conf/jail/flags', 0700 ) if !-e '/var/cpanel/conf/jail/flags';
        Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/conf/jail/flags/mount_usr_local_cpanel_3rdparty_mailman_suid');
    }
}

1;
