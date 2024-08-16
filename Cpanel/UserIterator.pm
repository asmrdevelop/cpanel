package Cpanel::UserIterator;

# cpanel - Cpanel/UserIterator.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::PwCache::Build          ();
use Cpanel::Config::LoadUserDomains ();

$Cpanel::UserIterator::VERSION = '1.0';

sub new {
    my $class = shift;
    my %OPTS  = @_;
    my $self  = {};
    bless $self, $class;
    Cpanel::PwCache::Build::init_passwdless_pwcache();
    $self->_load_userdomains() if ( $self->{'cpanel_only'} = $OPTS{'cpanel_only'} );
    $self->{'pwcache_ref'}      = Cpanel::PwCache::Build::fetch_pwcache();
    $self->{'pwcache_position'} = 0;
    $self->_find_next_cpanel_user() if $self->{'cpanel_only'};
    return $self;
}

sub _find_next_cpanel_user {
    my ($self) = @_;

    while ( $self->{'pwcache_ref'}->[ $self->{'pwcache_position'} ]
        && !$self->{'userdomains_ref'}{ $self->{'pwcache_ref'}->[ $self->{'pwcache_position'} ]->[0] } ) {
        ++$self->{'pwcache_position'};
    }
}

sub next {
    my ($self) = @_;
    ++$self->{'pwcache_position'};
    return $self->_find_next_cpanel_user() if $self->{'cpanel_only'};
    return $self->{'pwcache_position'};
}

sub pwref {
    my ($self) = @_;
    return $self->{'pwcache_ref'}->[ $self->{'pwcache_position'} ];
}

sub domains {
    my ($self) = @_;
    $self->_load_userdomains() if !exists $self->{'userdomains_ref'};
    return $self->{'userdomains_ref'}{ $self->{'pwcache_ref'}->[ $self->{'pwcache_position'} ]->[0] };
}

sub _load_userdomains {
    my ($self) = @_;
    $self->{'userdomains_ref'} = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 0, 1 );
}

sub user {
    $_[0]->{'pwcache_ref'}->[ $_[0]->{'pwcache_position'} ]->[0];
}

sub homedir {
    $_[0]->{'pwcache_ref'}->[ $_[0]->{'pwcache_position'} ]->[7];
}

1;
