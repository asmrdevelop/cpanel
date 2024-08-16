package Cpanel::PwCache;

# cpanel - Cpanel/PwCache.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Cached lookups to pw. Should be preferred generally to Perl built-ins
# when possible.
#
# getgr* functions are not implemented; for those, use Perl built-ins.
#
# XXX: This module is pretty tightly coupled with Cpanel::PwDiskCache.
# It would be good to rebuild these two modules at some point.
#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::PwCache - cache of pw datastore

=head1 SYNOPSIS

    my $uid = Cpanel::PwCache::getpwnam('some_username');
    my $username = Cpanel::PwCache::getpwuid(1234);

    my @pwdata;
    @pwdata = Cpanel::PwCache::getpwnam('some_username');
    @pwdata = Cpanel::PwCache::getpwnam_noshadow('some_username');

    @pwdata = Cpanel::PwCache::getpwuid(1234);
    @pwdata = Cpanel::PwCache::getpwuid_noshadow(1234);

    my $homedir;
    $homedir = Cpanel::PwCache::gethomedir('some_username');
    $homedir = Cpanel::PwCache::gethomedir(1234);

    my $cur_username = Cpanel::PwCache::getusername();

=head1 DESCRIPTION

Prefer these functions to Perl’s C<getpwnam()> and C<getpwuid()> built-ins
when possible.

Note that C<getgrnam()> and C<getgrgid()> are not implemented here.

=head1 MAIN FUNCTIONS

These are the replacements for Perl’s built-ins.

=cut

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Debug            ();
use Cpanel::NSCD::Check      ();
use Cpanel::PwCache::Helpers ();
use Cpanel::PwCache::Cache   ();
use Cpanel::PwCache::Find    ();

use constant DUMMY_PW_RETURNS => ( -1, -1, 0, 0 );
use constant DEBUG            => 0;                  # Must set $ENV{'CPANEL_DEBUG_LEVEL'} = 5 as well

our $VERSION = '4.2';

# These are the user we expect to have
# fixed user information.  If these are being
# changed the system is in a very broken
# state.
my %FIXED_KEYS = (
    '0:root'        => 1,
    '0:nobody'      => 1,
    '0:cpanel'      => 1,
    '0:cpanellogin' => 1,
    '0:mail'        => 1,
    '2:0'           => 1,
    '2:99'          => 1
);

#only used internally … and set by a test
our $_WANT_ENCRYPTED_PASSWORD;

=head2 getpwnam_noshadow() getpwuid_noshadow()

Like the corresponding Perl built-ins except for the extra returns
(see EXTRA RETURNS below); however, these will never
read F</etc/shadow>, so you’ll just get C<x> in place of the encrypted
password unless the password is already cached. This is significantly
faster than the “regular” functions which read the shadow datastore
in addition to pw.

Note that in scalar context these are functionally identical to
this module’s C<getpwnam()> and C<getpwuid()>.

=cut

sub getpwnam_noshadow {
    $_WANT_ENCRYPTED_PASSWORD = 0;
    goto &_getpwnam;
}

sub getpwuid_noshadow {
    $_WANT_ENCRYPTED_PASSWORD = 0;
    goto &_getpwuid;
}

=head2 getpwnam() getpwuid()

Like the non-shadow functions described above, but with data from
the shadow datastore like an encrypted password. Only call these
if you actually need the data; otherwise this is just
wasteful.

Note that in scalar context these are smart enough not to load
the shadow data, so there’s no harm in using these in scalar context.

=cut

sub getpwnam {
    $_WANT_ENCRYPTED_PASSWORD = !!wantarray;
    goto &_getpwnam;
}

sub getpwuid {
    $_WANT_ENCRYPTED_PASSWORD = !!wantarray;
    goto &_getpwuid;
}

#----------------------------------------------------------------------

=head1 CONVENIENCE FUNCTIONS

These just make life a little easier.

=head2 gethomedir() gethomedir( USERNAME )  gethomedir( UID )

Returns the home directory for the given user, or the effective user if
none is goven.

=cut

sub gethomedir {

    # Takes UID or USER as input arg, default to current EUID
    my $uid_or_name = $_[0] // $>;

    my $hd = Cpanel::PwCache::Cache::get_homedir_cache();

    unless ( exists $hd->{$uid_or_name} ) {
        $_WANT_ENCRYPTED_PASSWORD = 0;
        if ( $uid_or_name !~ tr{0-9}{}c ) {
            $hd->{$uid_or_name} = ( _getpwuid($uid_or_name) )[7];
        }
        else {
            $hd->{$uid_or_name} = ( _getpwnam($uid_or_name) )[7];
        }
    }

    return $hd->{$uid_or_name};
}

=head2 getusername() getusername( UID )

Returns the username for the given UID or, if none is given,
the effective user.

=cut

sub getusername {

    # Takes UID as input arg, default to current EUID
    my $uid = defined $_[0] ? $_[0] : $>;

    $_WANT_ENCRYPTED_PASSWORD = 0;
    return scalar _getpwuid($uid);
}

#----------------------------------------------------------------------

=head1 COMPATIBILITY FUNCTION

Don’t call this in new code.

=head2 init_passwdless_pwcache()

This has been moved to L<Cpanel::PwCache::Build>. Please see that
module for this function now.

=cut

=head1 EXTRA RETURNS

The C<getpw*> functions all return a total of B<13> items in scalar context.
The first 9 are the same you’ll receive from Perl’s built-ins: C<$name>,
C<$passwd>, C<$uid>, C<$gid>, C<$quota>, C<$comment>, C<$gcos>, C<$dir>,
and C<$shell>.

(NB: C<$expire>, described in Perl’s documentation, is not
returned on Linux.)

The remaining fields are:

                $SH[5],    #expire time
                $SH[2],    #change time
                $passwdmtime,
                $shadowmtime

=over

=item Days prior to password expiration that the user is
warned of pending password expiration. (cf. C<man shadow>, C<sp_warn>)
This defaults to -1 if it is unavailable.

=item Days since 1 Jan 1970 when the password was last changed.
(cf. C<man shadow>, C<sp_lstchg>) This defaults to -1 if it is unavailable.

=item The modification time of the pw datastore (F</etc/passwd>),
in epoch time.  This defaults to 0 if it is unavailable.

=item The modification time of the shadow datastore
(F</etc/shadow>), in epoch time. This defaults to 0 if it is unavailable.

=back

=cut

# here for backward compatibility reasons (tomcat)
sub init_passwdless_pwcache {
    require Cpanel::PwCache::Build;
    *init_passwdless_pwcache = \&Cpanel::PwCache::Build::init_passwdless_pwcache;
    goto &Cpanel::PwCache::Build::init_passwdless_pwcache;
}

#----------------------------------------------------------------------

# $_[0] = UID
sub _getpwuid {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return unless ( length( $_[0] ) && $_[0] !~ tr/0-9//c );

    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();

    if ( !exists $pwcache_ref->{"2:$_[0]"} && $> != 0 && !Cpanel::PwCache::Helpers::istied() && Cpanel::NSCD::Check::nscd_is_running() ) {
        return CORE::getpwuid( $_[0] ) if !wantarray;

        my @ret = CORE::getpwuid( $_[0] );

        return @ret ? ( @ret, DUMMY_PW_RETURNS() ) : ();
    }

    #confess if -e '/etc/cpanel_build';
    if ( my $pwref = _pwfunc( $_[0], 2 ) ) {
        return wantarray ? @$pwref : $pwref->[0];
    }
    return;    #important not to return 0
}

# $_[0] = username
sub _getpwnam {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return unless ( length( $_[0] ) && $_[0] !~ tr{\x{00}-\x{20}\x{7f}:/#}{} );

    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();

    if ( !exists $pwcache_ref->{"0:$_[0]"} && $> != 0 && !Cpanel::PwCache::Helpers::istied() && Cpanel::NSCD::Check::nscd_is_running() ) {
        return CORE::getpwnam( $_[0] ) if !wantarray;

        my @ret = CORE::getpwnam( $_[0] );

        return @ret ? ( @ret, DUMMY_PW_RETURNS() ) : ();
    }

    #confess if -e '/etc/cpanel_build';
    if ( my $pwref = _pwfunc( $_[0], 0 ) ) {
        return wantarray ? @$pwref : $pwref->[2];
    }
    return;    #important not to return 0
}

#called directly from a test
sub _pwfunc {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my ( $value, $field, $pwkey ) = ( $_[0], ( $_[1] || 0 ), $_[1] . ':' . ( $_[0] || 0 ) );

    if ( Cpanel::PwCache::Helpers::istied() ) {

        # ::validate will make sure this is valid!
        Cpanel::Debug::log_debug("cache tie (tied) value[$value] field[$field]") if (DEBUG);
        my $pwcachetie = Cpanel::PwCache::Helpers::tiedto();

        if ( ref $pwcachetie eq 'HASH' ) {
            my $cache = $pwcachetie->{$pwkey};
            if ( ref $cache eq 'HASH' ) {
                return $pwcachetie->{$pwkey}->{'contents'};
            }
        }
        return undef;
    }
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();

    # We only lookup the encrypted password in
    # /etc/shadow if the caller wants it.
    my $lookup_encrypted_pass = 0;
    if ($_WANT_ENCRYPTED_PASSWORD) {

        # .. and we only do the lookup if we are
        # root.
        $lookup_encrypted_pass = $> == 0 ? 1 : 0;
    }

    my ( $passwdmtime, $hpasswdmtime );

    my $pwcache_ref = Cpanel::PwCache::Cache::get_cache();

    # Make sure reference object is loaded before evaluating
    if ( my $cache_entry = $pwcache_ref->{$pwkey} ) {
        Cpanel::Debug::log_debug("exists in cache value[$value] field[$field]") if (DEBUG);
        if (
            ( exists( $cache_entry->{'contents'} ) && $cache_entry->{'contents'}->[1] ne 'x' )    # Has shadow entry
            || !$lookup_encrypted_pass                                                            # Or we do not need it
          ) {                                                                                     # If we are root and missing the password field we could fail authentication
            if ( $FIXED_KEYS{$pwkey} ) {                                                          # We assume root, nobody, and cpanellogin will never change during execution
                Cpanel::Debug::log_debug("cache (never change) hit value[$value] field[$field]") if (DEBUG);
                return $cache_entry->{'contents'};
            }

            $passwdmtime  = ( stat("$SYSTEM_CONF_DIR/passwd") )[9];
            $hpasswdmtime = $lookup_encrypted_pass ? ( stat("$SYSTEM_CONF_DIR/shadow") )[9] : 0;

            if (   ( $lookup_encrypted_pass && $hpasswdmtime && $hpasswdmtime != $cache_entry->{'hcachetime'} )
                || ( $passwdmtime && $passwdmtime != $cache_entry->{'cachetime'} ) ) {    #timewarp safe
                DEBUG && Cpanel::Debug::log_debug( "cache miss value[$value] field[$field] pwkey[$pwkey] " . qq{hpasswdmtime: $hpasswdmtime != $cache_entry->{hcachetime} } . qq{passwdmtime: $passwdmtime != $cache_entry->{cachetime} } );

                if ( defined $cache_entry && defined $cache_entry->{'contents'} ) {

                    #If the passwd file mtime changes everything is invalid
                    # The whole cache is invalid since there is only
                    # one mtime and one file
                    Cpanel::PwCache::Cache::clear();    #If the passwd file mtime changes everything is invalid
                }
            }
            else {
                Cpanel::Debug::log_debug("cache hit value[$value] field[$field]") if (DEBUG);
                return $cache_entry->{'contents'};
            }
        }
        elsif (DEBUG) {
            Cpanel::Debug::log_debug( "cache miss pwkey[$pwkey] value[$value] field[$field] passwdmtime[$passwdmtime] pwcacheistied[" . Cpanel::PwCache::Helpers::istied() . "] hpasswdmtime[$hpasswdmtime]" );
        }
    }
    elsif (DEBUG) {
        Cpanel::Debug::log_debug( "cache miss (no entry) pwkey[$pwkey] value[$value] field[$field] pwcacheistied[" . Cpanel::PwCache::Helpers::istied() . "]" );
    }
    my $pwdata = _getpwdata( $value, $field, $passwdmtime, $hpasswdmtime, $lookup_encrypted_pass );

    _cache_pwdata( $pwdata, $pwcache_ref ) if $pwdata && @$pwdata;

    return $pwdata;
}

#NB: this gets called directly from Cppanel::PwCache::Load.
sub _getpwdata {
    my ( $value, $field, $passwdmtime, $shadowmtime, $lookup_encrypted_pass ) = @_;
    return if ( !defined $value || !defined $field || $value =~ tr/\0// );

    if ($lookup_encrypted_pass) {
        return [ _readshadow( $value, $field, $passwdmtime, $shadowmtime ) ];
    }

    return [ _readpasswd( $value, $field, $passwdmtime, $shadowmtime ) ];
}

sub _readshadow {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    my ( $value, $field, $passwdmtime, $shadowmtime ) = ( $_[0], ( $_[1] || 0 ), ( $_[2] || ( stat("$SYSTEM_CONF_DIR/passwd") )[9] ), ( $_[3] || ( stat("$SYSTEM_CONF_DIR/shadow") )[9] ) );
    my @PW = _readpasswd( $value, $field, $passwdmtime, $shadowmtime );
    return if !@PW;

    $value = $PW[0];

    if ( open my $shadow_fh, '<', "$SYSTEM_CONF_DIR/shadow" ) {
        if ( my @SH = Cpanel::PwCache::Find::field_with_value_in_pw_file( $shadow_fh, 0, $value ) ) {

            # Always returns array context
            ( $PW[1], $PW[9], $PW[10], $PW[11], $PW[12] ) = (
                $SH[1],    #encrypted pass
                $SH[5],    #expire time
                $SH[2],    #change time
                $passwdmtime,
                $shadowmtime
            );
            close $shadow_fh;
            Cpanel::PwCache::Cache::is_safe(0);
            return @PW;
        }
    }
    else {
        Cpanel::PwCache::Helpers::cluck("Unable to open $SYSTEM_CONF_DIR/shadow: $!");
    }

    Cpanel::PwCache::Helpers::cluck("Entry for $value missing in $SYSTEM_CONF_DIR/shadow");
    return @PW;
}

sub _readpasswd {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    my ( $value, $field, $passwdmtime, $shadowmtime, $block ) = ( $_[0], ( $_[1] || 0 ), ( $_[2] || ( stat("$SYSTEM_CONF_DIR/passwd") )[9] ), $_[3] );

    if ( $INC{'B/C.pm'} ) {
        die("Cpanel::PwCache::_readpasswd cannot be run under B::C (see case 162857)");
    }

    # Previously we called getpwent to go though the file
    # This proved to be very slow with large password files because of all the
    # OPS required to switch subs
    if ( open( my $passwd_fh, '<', "$SYSTEM_CONF_DIR/passwd" ) ) {
        if ( my @PW = Cpanel::PwCache::Find::field_with_value_in_pw_file( $passwd_fh, $field, $value ) ) {

            # Always returns array context
            return ( $PW[0], $PW[1], $PW[2], $PW[3], '', '', $PW[4], $PW[5], $PW[6], -1, -1, $passwdmtime, ( $shadowmtime || $passwdmtime ) );
        }
        close($passwd_fh);
    }
    else {
        Cpanel::PwCache::Helpers::cluck("open($SYSTEM_CONF_DIR/passwd): $!");
    }

    return;
}

sub _cache_pwdata {
    my ( $pwdata, $pwcache_ref ) = @_;

    $pwcache_ref ||= Cpanel::PwCache::Cache::get_cache();

    if ( $pwdata->[2] != 0 || $pwdata->[0] eq 'root' ) {    # special case for multiple uid 0 users
        @{ $pwcache_ref->{ '2' . ':' . $pwdata->[2] } }{ 'cachetime', 'hcachetime', 'contents' } = ( $pwdata->[11], $pwdata->[12], $pwdata );
    }
    @{ $pwcache_ref->{ '0' . ':' . $pwdata->[0] } }{ 'cachetime', 'hcachetime', 'contents' } = ( $pwdata->[11], $pwdata->[12], $pwdata );
    return 1;
}

1;
