package Whostmgr::Transfers::Systems::Integration;

# cpanel - Whostmgr/Transfers/Systems/Integration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module must “mirror” Cpanel::Pkgacct::Components::Integration.
#----------------------------------------------------------------------

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Try::Tiny;

use parent qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Imports;

use Cpanel::Exception           ();
use Cpanel::FileUtils::Dir      ();
use Cpanel::Integration::Config ();
use Cpanel::JSON                ();
use Whostmgr::Integration       ();

sub unrestricted_restore {
    my ($self) = @_;

    my $edir = $self->extractdir();

    my $links_dir = "$edir/integration/links";

    local $SIG{'__WARN__'} = sub { $self->warn(@_) };

    #NOTE: This directory should only contain two kinds of files: the
    #user-config, and the admin-config files. Anything else is unrecognized
    #and should prompt a warning.
    if ( -d $links_dir ) {
        my $nodes_ar      = Cpanel::FileUtils::Dir::get_directory_nodes($links_dir);
        my $userconfig_re = qr<\.\Q$Cpanel::Integration::Config::USER_CONFIG_FILE_SUFFIX\E\z>;

        my @apps = grep { m<$userconfig_re> } @$nodes_ar;
        s<$userconfig_re><> for @apps;

        my %nodes_lookup = map { $_ => undef } @$nodes_ar;

        for my $app (@apps) {
            my $links_data_file = "$app.$Cpanel::Integration::Config::USER_CONFIG_FILE_SUFFIX";
            my $links_data_path = "$links_dir/$links_data_file";

            my $link_data_hr = Cpanel::JSON::LoadFile($links_data_path);

            my $token_data_file = "$app.$Cpanel::Integration::Config::ADMIN_CONFIG_FILE_SUFFIX";
            my $token_file_path = "$links_dir/$token_data_file";

            if ( -e $token_file_path ) {
                try {
                    my $token_hr = Cpanel::JSON::LoadFile($token_file_path);
                    if ( $token_hr->{'token'} ) {
                        $link_data_hr->{'token'} = $token_hr->{'token'};
                    }
                }
                catch {
                    $self->warn( locale()->maketext( "The system failed to extract a valid “[_1]” from the file “[_2]” because of an error: [_3]", 'token', $token_file_path, Cpanel::Exception::get_string($_) ) );
                };
            }

            if ( $app =~ m{^\Q$Cpanel::Integration::Config::GROUP_PREFIX\E} ) {
                my $group = $app;
                $group =~ s{^\Q$Cpanel::Integration::Config::GROUP_PREFIX\E}{};
                try {
                    Whostmgr::Integration::add_group(
                        $self->newuser(),
                        $group,
                        $link_data_hr,
                    );
                }
                catch {
                    $self->warn( locale()->maketext( "The system failed to restore the integration group for the application “[_1]” because of an error: [_2]", $app, Cpanel::Exception::get_string($_) ) );
                };
            }
            else {
                try {
                    $self->out( locale()->maketext( "Restoring the integration link for the application “[_1]” …", $app ) );
                    Whostmgr::Integration::add_link(
                        $self->newuser(),
                        $app,
                        $link_data_hr,
                    );
                }
                catch {
                    $self->warn( locale()->maketext( "The system failed to restore the integration link for the application “[_1]” because of an error: [_2]", $app, Cpanel::Exception::get_string($_) ) );
                };
            }

            delete @nodes_lookup{ $links_data_file, $token_data_file };
        }

        for my $unrecognized ( sort keys %nodes_lookup ) {
            $self->warn( locale()->maketext( 'The system has skipped the unrecognized file “[_1]”.', $unrecognized ) );
        }
    }

    return 1;
}

*restricted_restore = \&unrestricted_restore;

1;
