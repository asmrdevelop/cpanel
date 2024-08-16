package Cpanel::Plugins::Repo;

# cpanel - Cpanel/Plugins/Repo.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Plugins::Repo - Install/remove the cP plugins yum/apt repository.

=head1 SYNOPSIS

    Cpanel::Plugins::Repo::install();

    Cpanel::Plugins::Repo::uninstall();

    if ( Cpanel::Plugins::Repo::is_installed() ) { ... }

    my $txt = Cpanel::Plugins::Repo::get_config();

=cut

#----------------------------------------------------------------------

use Cpanel::Config::Sources  ();
use Cpanel::Autodie          ();
use Cpanel::FileUtils::Write ();
use Cpanel::HTTP::Client     ();
use Cpanel::OS               ();
use Cpanel::Exception        ();

our $_REPO_URL;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 NAME

Returns the repo name as yum/apt recognize it.

=cut

use constant NAME => 'cpanel-plugins';

=head2 install()

Downloads and installs the cPanel plugins repository file.
This overwrites any currently-installed copy of the file.

=cut

sub install {
    my $repo_config_path = _repo_config_path();
    my $repo_conf        = get_config();
    return unless Cpanel::OS::supports_plugins_repo();
    Cpanel::FileUtils::Write::overwrite( $repo_config_path, $repo_conf->{'raw'} );

    return;
}

=head2 uninstall()

Returns 1 if the respository file is removed, or 0 otherwise.

=cut

sub uninstall {
    return Cpanel::Autodie::unlink_if_exists( _repo_config_path() );
}

=head2 $yn = is_installed()

Returns boolean truthy or falsy to indicate whether the cPanel plugins
repository is currently installed.

=cut

sub is_installed {
    return Cpanel::Autodie::exists( _repo_config_path() );
}

=head2 $content_hr = get_config()

Downloads and returns the cPanel plugins repository configuration file
content in both raw and cooked form. This does NOT use a local cache.

The returned hashref will always provide the raw repository configuration
in the C<raw> key. If the fetched configuration specifies list of mirrors
using Yum's C<mirrorlist> option or Apt's L<mirror://> URL, this function
will populate the C<mirrorurl> key with the HTTP URL being used to fetch
the list of mirrors, and the C<baseurls> key with an arrayref of the URLs
fetched. If the config uses Yum's C<baseurls> option directly or specifies
a normal HTTP URL to Apt, that URL will appear in an arrayref in the
C<baseurls> key.

If there is an error, this function will throw an exception.

=cut

sub get_config {

    my %config;

    # Delete the cpanel-plugins.repo.* files and the enable-bwg-repo script before
    # doing an upstream merge. Delete this entire condition if the ability to override
    # the retrieval of this file on a binary build is found to be undesirable.
    # Note that now this is used in sandbox bootstrap to override httpupdate as well.
    my $plugins_repo_file = Cpanel::Config::Sources::get_source('CPANEL_PLUGINS');
    if ( defined $plugins_repo_file && length $plugins_repo_file && -f $plugins_repo_file ) {
        require Cpanel::LoadFile;
        $config{'raw'} = Cpanel::LoadFile::load($plugins_repo_file);
    }
    else {
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();
        $config{'raw'} = $http->get( _repo_url() )->content();
    }

    my ($mirrorurl) = $config{'raw'} =~ m<^mirrorlist\s*=\s*([^\n]+)>m;
    if ( !$mirrorurl ) {
        ($mirrorurl) = $config{'raw'} =~ m<^deb\s+(?:\[[^\]]*\]\s+)?(mirror://.+?)\s+.+$>m;
    }
    my ($baseurl) = $config{'raw'} =~ m<^baseurl\s*=\s*([^\n]+)>m;
    if ( !$baseurl ) {
        ($baseurl) = $config{'raw'} =~ m<^deb\s+(?:\[[^\]]*\]\s+)?([a-z]+tp[s]?://\S+)>m;
    }

    if ($mirrorurl) {
        $mirrorurl = _do_url_variable_substitution($mirrorurl);

        # Has to be a protocol an HTTP client can use, not something meaningful only to apt:
        $mirrorurl =~ s/mirror\:\/\//http\:\/\//;

        $config{'mirrorurl'} = $mirrorurl;

        require Cpanel::HTTP::Client;
        my $http = Cpanel::HTTP::Client->new()->die_on_http_error();

        my $list_txt = $http->get($mirrorurl)->content();
        my @urls     = split m<(?:\r?\n)+>, $list_txt;

        # Choose a place to start at random.
        my $index = int( rand() * @urls );

        # “Roll” the array so that we start at $index.
        # We could alternatively shuffle(); the idea is that
        # we want to distribute the load evenly among @urls
        # across cPanel & WHM installations.
        push( @urls, splice( @urls, 0, $index ) );

        $config{'baseurls'} = \@urls;
    }
    elsif ($baseurl) {
        $config{'baseurls'} = [ _do_url_variable_substitution($baseurl) ];
    }
    else {
        die Cpanel::Exception->create_raw( "cPanel plugins repo configuration doesn’t contain a “mirrorlist” or “baseurl”: " . $config{'raw'} );
    }

    return \%config;
}

#----------------------------------------------------------------------

sub _do_url_variable_substitution ($input) {
    my $releasever = Cpanel::OS::major();    ## no critic(Cpanel::CpanelOS) major is used by templates

    my %var = (
        basearch => 'x86_64',

        # This variable isn’t alwys what we expect …
        releasever => $releasever,

        # … so we use this variable now.
        cp_centos_major_version => $releasever,
    );

    return ( $input =~ s<\$([_a-z]+)><$var{$1}>gr );
}

sub _repo_url {
    return $_REPO_URL ||= Cpanel::OS::plugins_repo_url();
}

#called from tests
sub _repo_config_path {
    my $repo_path   = Cpanel::OS::repo_dir();
    my $repo_suffix = Cpanel::OS::repo_suffix();
    return "$repo_path/" . NAME() . ".$repo_suffix";
}

1;
