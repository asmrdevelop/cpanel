package Cpanel::Mailman::Config::User;

# cpanel - Cpanel/Mailman/Config/User.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::PwCache                 ();
use Cpanel::AdminBin::Call          ();
use Cpanel::Mailman::Config::Object ();
use Cpanel::Mailman::Filesys        ();
use Cpanel::SafeDir::MK             ();

#Constant
my $CREATE_IF_NEEDED = 1;

sub new {
    my ( $class, %opts ) = @_;

    my @effective_pwnam = Cpanel::PwCache::getpwuid($>);

    if ( $effective_pwnam[2] == 0 ) {
        die "This package: " . __PACKAGE__ . " may not be run as root.";
    }

    my $self = {
        'homedir' => $effective_pwnam[7],
        'listids' => (
            $opts{'listids'}
            ? { map { $_ => undef } @{ $opts{'listids'} } }
            : {}
        )

    };

    bless $self, $class;

    $self->_recache_mailmanconfig_if_needed();

    return $self;
}

sub fetch_config {
    my ( $self, $listid ) = @_;

    if ( !exists $self->{'listids'}{$listid} ) {
        $self->{'listids'}{$listid} = undef;
        $self->_recache_mailmanconfig_if_needed();
    }

    my $configcache_dir = $self->_configcache_dir();

    # The cache has a limited set of keys as defined in
    # ULC/lib/python2/cPanel.py export_cpanel_pickle_keys_as_json
    my $config_file = "$configcache_dir/$listid";

    if ( -e $config_file ) {
        return Cpanel::Mailman::Config::Object->new($config_file);
    }

    return;
}

sub purge {
    my ( $self, $listid ) = @_;

    die "listid may not contain a /" if $listid =~ m{/};

    my $configcache_dir = $self->_configcache_dir();

    delete $self->{'listids'}{$listid};

    return 1 if !-e "$configcache_dir/$listid";

    return unlink("$configcache_dir/$listid");
}

#NOTE: Overridden in tests.
sub _recache_mailmanconfig_if_needed {
    my ($self) = @_;

    my @ids = keys %{ $self->{'listids'} };

    if ( $self->_mailmanconfig_needs_rebuild() ) {
        return Cpanel::AdminBin::Call::call( 'Cpanel', 'list', 'RECACHE_CONFIGURATION', \@ids );
    }

    return 1;
}

sub _configcache_dir {
    my ( $self, $should_create ) = @_;

    my $configcache_dir = $self->{'homedir'} . Cpanel::Mailman::Filesys::CONFIGCACHE_DIR_REL_HOMEDIR();

    if ( $should_create && $should_create == $CREATE_IF_NEEDED && !-e $configcache_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $configcache_dir, 0700 ) || die "Failed to create $configcache_dir: $!";
    }

    return $configcache_dir;

}

sub _mailmanconfig_needs_rebuild {
    my ($self) = @_;

    return 0 if !$self->{'listids'};

    my $listids = [ keys %{ $self->{'listids'} } ];

    my $configcache_dir   = $self->_configcache_dir();
    my $MAILING_LISTS_DIR = Cpanel::Mailman::Filesys::MAILING_LISTS_DIR();

    my $needs_rebuild_cache = 0;

    foreach my $listid ( @{$listids} ) {
        my $cache_mtime  = ( stat( $configcache_dir . '/' . $listid ) )[9];
        my $config_pck   = Cpanel::Mailman::Filesys::get_list_dir($listid) . '/config.pck';
        my $config_mtime = ( stat($config_pck) )[9];

        if ( !$config_mtime || !$cache_mtime || $config_mtime >= $cache_mtime ) {
            $needs_rebuild_cache = 1;
            last;
        }
    }

    return $needs_rebuild_cache;
}

1;
