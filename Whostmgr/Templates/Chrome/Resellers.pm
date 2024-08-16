package Whostmgr::Templates::Chrome::Resellers;

# cpanel - Whostmgr/Templates/Chrome/Resellers.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig        ();
use Cpanel::ConfigFiles               ();
use Cpanel::Template::Plugin::Command ();

use Whostmgr::ACLS                          ();
use Whostmgr::Templates::Chrome             ();
use Whostmgr::Templates::Chrome::Directory  ();
use Whostmgr::Templates::Command            ();
use Whostmgr::Templates::Command::Directory ();

my $list_of_resellers;
my $processed_keys;

=head1 DESCRIPTION

Utility functions to process cached WHM chrome files for resellers

=head1 SUBROUTINES

=head2 _get_resellers_list

=head3 Purpose

Get a list of all resellers on the system

=cut

sub _get_resellers_list {
    return $list_of_resellers if $list_of_resellers;

    my $resellers_file = Cpanel::Config::LoadConfig::loadConfig( $Cpanel::ConfigFiles::RESELLERS_FILE, undef, ':' );
    $list_of_resellers = [ 'root', keys %{$resellers_file} ];

    return $list_of_resellers;
}

=head2 _process_reseller

=head3 Purpose

Process _defheader.tmpl and cache result for one reseller

=cut

sub _process_reseller {
    my ( $reseller, $args ) = @_;

    # process/load correct user command.tmpl
    %Whostmgr::ACLS::ACL = ();
    local $ENV{'REMOTE_USER'} = $reseller;
    Whostmgr::ACLS::init_acls();

    Whostmgr::Templates::Command::clear_cache();
    Whostmgr::Templates::Command::clear_cache_key();
    Whostmgr::Templates::Command::cached_load();

    Cpanel::Template::Plugin::Command::clear_cache();

    my $cache_key = Whostmgr::Templates::Command::get_cache_key();

    return $cache_key if $processed_keys->{$cache_key};

    Whostmgr::Templates::Chrome::process_header($args);
    $processed_keys->{$cache_key} = 1;

    return $cache_key;
}

=head2 process_all_resellers

=head3 Purpose

Process cached WHM header files for all resellers

=cut

sub process_all_resellers {
    Whostmgr::Templates::Command::Directory::clear_cache_dir();
    Whostmgr::Templates::Chrome::Directory::clear_cache_directories();
    Whostmgr::ACLS::get_dynamic_acl_lists();

    process_footer();

    $list_of_resellers ||= _get_resellers_list();
    my $user_cache_keys = {};

    my @opts = ();
    push @opts, { 'skipheader' => 1, 'skipsupport' => 1 };
    push @opts, { 'skipheader' => 1, 'skipsupport' => 0 };
    push @opts, { 'skipheader' => 0, 'skipsupport' => 1 };
    push @opts, { 'skipheader' => 0, 'skipsupport' => 0 };

    local $ENV{'BATCH_RESELLERS_PROCESSING'} = 1;

    foreach my $args (@opts) {
        $processed_keys = {};
        foreach my $reseller ( @{$list_of_resellers} ) {
            my $cache_key = _process_reseller( $reseller, $args );
            $user_cache_keys->{$reseller} = $cache_key unless $user_cache_keys->{$reseller};
        }
    }

    return $user_cache_keys;
}

*process_footer = \&Whostmgr::Templates::Chrome::process_footer;

1;
