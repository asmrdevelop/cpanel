package Cpanel::AcctUtils::DomainOwner::Tiny;

# cpanel - Cpanel/AcctUtils/DomainOwner/Tiny.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles           ();
use Cpanel::FileLookup            ();
use Cpanel::Config::HasCpUserFile ();

my $domainowner_cache_hr;
my $true_domainowner_cache_hr;

our $CACHE_IS_SET           = 0;
our $DEFAULT_USER_TO_RETURN = 'root';

=head1 FUNCTIONS

=cut

sub get_cache {
    return $domainowner_cache_hr;
}

sub build_truedomain_cache {
    require Cpanel::Config::LoadUserDomains;
    return ( $true_domainowner_cache_hr = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 ) );
}

sub build_domain_cache {
    require Cpanel::Config::LoadUserDomains;
    $CACHE_IS_SET         = 1;
    $domainowner_cache_hr = scalar Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    return $domainowner_cache_hr;
}

sub clearcache {
    $CACHE_IS_SET              = 0;
    $domainowner_cache_hr      = {};
    $true_domainowner_cache_hr = {};
    return 1;
}

=head2 getdomainowner($domain, [$options])

Return the owner of the domain in question, or C<$options-E<gt>{'default'}> if
there is no owner or the owner cannot be determined.

This function will work for non-root users only if the domain being queried is
owned by the user.

=cut

sub getdomainowner {
    my $owner = ( _getdomainowner(@_) )[0];

    # Avoid calling getdomainowner_with_reason since it will
    # increase our call stack for a function that is called
    # 100000+ times during a restore
    return $owner eq $DEFAULT_USER_TO_RETURN ? ( exists $_[1]->{'default'} ? $_[1]->{'default'} : $owner ) : $owner;
}

=head2 getdomainowner_with_reason($domain, [$options])

Return a list of two items.  The first item is the owner of the domain in
question, or C<$options-E<gt>{'default'}> if there is no owner or the owner
cannot be determined.  The second item, if provided, is a reason in the form of
a sentence, explaining why we think this user owns (or does not own) the domain.
It may be missing if a reason cannot be determined.

This function will work for non-root users only if the domain being queried is
owned by the user.

=cut

sub getdomainowner_with_reason {

    # This function will work when running as a non-root user, however only for domains owned by that user.
    my ( $owner, $reason ) = _getdomainowner(@_);

    #exists because we may want '' or undef
    if ( $owner eq $DEFAULT_USER_TO_RETURN ) {
        $owner = $_[1]->{'default'} if exists $_[1]->{'default'};
    }
    return ( $owner, $reason );
}

sub _set_cache {
    my ( $domain, $user, $reason ) = @_;
    my $entry = $domainowner_cache_hr->{$domain} = [ $user, $reason ];
    return @$entry;
}

sub domain_has_owner {
    return ( _getdomainowner( $_[0], { 'skiptruelookup' => 1 } ) )[0] eq $DEFAULT_USER_TO_RETURN ? 0 : 1;
}

# CACHING: We must only cache positive hits, we should never
# cache if the user does not exist.
#
# Returns the domain owner and possibly a reason why we think that result is
# accurate.
sub _getdomainowner {    ## no critic qw(RequireArgUnpacking)
    return ($DEFAULT_USER_TO_RETURN)                                                                                           if ( length( $_[0] ) > 255 || length( $_[0] ) < 3 || $_[0] =~ tr{a-z0-9_.*-}{}c || index( $_[0], '..' ) != -1 );
    return ref $domainowner_cache_hr->{ $_[0] } ? @{ $domainowner_cache_hr->{ $_[0] } } : ( $domainowner_cache_hr->{ $_[0] } ) if exists $domainowner_cache_hr->{ $_[0] };

    # Note: Cpanel::Userdomains::updateuserdomains calls clearcache()
    # to ensure this does not break for newly created domains
    return ($DEFAULT_USER_TO_RETURN) if $CACHE_IS_SET;    # If the cache is built no need to fall back since we have everything in memory

    # Unpacking @_ deferred since this can get called 10k+ times
    # in a tight loop from dovecotSNI.pm
    my ( $domain, $opref ) = @_;

    if ( index( $domain, '*' ) == -1 ) {

        # Valiases is authoritative since its root owned
        # and we validate there is a real cpanel user owning
        # it to avoid cruft
        if ( my $uid = ( stat("$Cpanel::ConfigFiles::VALIASES_DIR/$domain") )[4] ) {
            local $@;
            eval 'require Cpanel::PwCache;' if !$INC{'Cpanel/PwCache.pm'};    ## no critic(ProhibitStringyEval)
            if ( !$@ ) {
                my $valias_user = ( 'Cpanel::PwCache'->can('getpwuid_noshadow')->($uid) )[0];
                if ( Cpanel::Config::HasCpUserFile::has_cpuser_file($valias_user) ) {
                    return _set_cache( $domain, $valias_user, 'A valiases file exists for this domain.' );
                }
            }

            # We do not die here if load fails because we can try another method below
            # and still have a chance to get an authoritative answer
        }
    }

    my $is_root = $> == 0 ? 1 : 0;
    my $owner;
    if ( !$opref->{'skiptruelookup'} && ( $is_root || -r $Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE ) ) {
        $owner = Cpanel::FileLookup::filelookup( $Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE, 'key' => $domain );
    }
    if ( !$owner && ( $is_root || -r $Cpanel::ConfigFiles::USERDOMAINS_FILE ) ) {
        $owner = Cpanel::FileLookup::filelookup( $Cpanel::ConfigFiles::USERDOMAINS_FILE, 'key' => $domain );
    }

    if ($owner) {
        return _set_cache( $domain, $owner, 'A userdomains entry exists for this domain.' );
    }

    if ( !$is_root ) {
        local $@;
        eval 'require Cpanel::Config::LoadCpUserFile; require Cpanel::Config::HasCpUserFile; require Cpanel::PwCache;';    ## no critic qw(ProhibitStringyEval) -- quoted eval to hide this from perlcc
        if ( !$@ ) {
            my $current_user = ( Cpanel::PwCache::getpwuid($>) )[0];
            if ( Cpanel::Config::HasCpUserFile::has_readable_cpuser_file($current_user) ) {
                my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($current_user);
                if ( $cpuser_ref && ( $cpuser_ref->{'DOMAIN'} eq $domain || grep { $_ eq $domain } @{ $cpuser_ref->{'DOMAINS'} } ) ) {
                    return _set_cache( $domain, $current_user, "This domain is in the current user's cpuser file." );
                }
            }
        }
        else {
            # Cannot load logger here due to memory requirements so just die.
            die "Failed to load Cpanel::Config::LoadCpUserFile or Cpanel::PwCache: $@";

        }
    }

    return ($DEFAULT_USER_TO_RETURN);
}

1;
