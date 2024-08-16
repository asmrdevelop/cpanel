package Cpanel::Config::userdata::Load;

# cpanel - Cpanel/Config/userdata/Load.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context                     ();
use Cpanel::CachedDataStore             ();
use Cpanel::Config::userdata::Constants ();
use Cpanel::Debug                       ();

use constant {
    _EPERM  => 1,
    _EACCES => 13,
    _ENOENT => 2,
};

# Constant
our $ADDON_DOMAIN_CHECK_DO   = 0;
our $ADDON_DOMAIN_CHECK_SKIP = 1;

sub load_userdata_main {
    my ($user) = @_;
    my $userdata_ref = load_userdata( $user, 'main' );    # Don't lock, just reading.

    require Cpanel::Config::userdata::Utils;

    # Sanity check data structure
    Cpanel::Config::userdata::Utils::sanitize_main_userdata($userdata_ref);

    return $userdata_ref;
}

#This is inaccurately named; you actually submit a vhost name
#(user-created subdomain or main domain), not just any domain.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for logic to fetch the vhost name for a given domain.
sub load_ssl_domain_userdata {
    my ( $user, $domain, $skip_addon_domain_check ) = @_;

    my $file = $domain . '_SSL';

    return load_userdata( $user, $file, $skip_addon_domain_check );
}

sub load_userdata {
    my ( $user, $file, $skip_addon_domain_check ) = @_;

    $file = 'main' if !defined $file;
    my $path = $Cpanel::Config::userdata::Constants::USERDATA_DIR . '/' . $user . '/' . $file;

    # Case 44627: if it is an addon, look for the subdomain instead.
    if ( !$skip_addon_domain_check && $file ne 'main' && !-e $path ) {    # !$skip_addon_domain_check means $ADDON_DOMAIN_CHECK_DO
        my $userdata_ref = load_userdata_main($user);
        my $test_file    = ( split( /_SSL$/, $file ) )[0];
        if ( $userdata_ref->{'addon_domains'}->{$test_file} ) {
            $file = $userdata_ref->{'addon_domains'}->{$test_file} . ( ( $file =~ m/_SSL$/ ) ? '_SSL' : '' );
            $path = $Cpanel::Config::userdata::Constants::USERDATA_DIR . '/' . $user . '/' . $file;
        }
    }

    # Usage is safe as we own the file and dir
    my $ref = Cpanel::CachedDataStore::loaddatastore(
        $path,
        undef,
        undef,
        { donotlock => ( $> != 0 ) },    #don’t lock if we aren’t root
    );

    # If the file can't be read, return an empty hash; log a warning if this was due to file permissions.
    # It's okay if we failed to read the file because it doesn't exist; that happens normally during account creation
    ## FIXME?: we can no longer use this function in a conditional, as it never produces a false value;
    ##   see DomainLookup's &getdocroot; per the above comment, it would be better to have more fault
    ##   tolerant code in account creation than to return essentially a "null object pattern"
    if ( !$ref || !$ref->{'data'} ) {
        local $!;
        if ( !-r $path && ( $! == _EPERM() || $! == _EACCES() ) ) {
            die("Userdata file '$file' for user '$user' is not readable: $!");
        }
        return {};
    }

    # Clone the data to preserve fetch_ref behavior now that we use
    # loaddatastore.  Note that our data may be either a hashref or an arrayref.
    # This was originally fixed by Cpanel::AdminBin::Serializer::clone which
    # turned out to have a problem with utf-8 data.  It was since changed to
    # replicate the shallow clone in Cpanel::CachedDataStore to exactly
    # perserve previous behavior.
    $ref = Cpanel::CachedDataStore::top_level_clone( $ref->{'data'} );

    #Trailing slashes can happen if the datastore is manually altered.
    if ( ref($ref) eq 'HASH' && $ref->{'documentroot'} && substr( $ref->{'documentroot'}, -1 ) eq '/' ) {
        substr( $ref->{'documentroot'}, -1 ) = q<>;
    }

    return $ref;
}

#This is inaccurately named; you actually submit a vhost name
#(user-created subdomain or main domain), not just any domain.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for logic to fetch the vhost name for a given domain.
sub load_userdata_domain_or_die {
    my ( $user, $file, $skip_addon_domain_check ) = @_;

    my $ud_hr = load_userdata( $user, $file, $skip_addon_domain_check );
    if ( !$ud_hr || !%$ud_hr ) {
        die "Failed to load userdata for “$file” ($user)!";
    }

    return $ud_hr;
}

#This is inaccurately named; you actually submit a vhost name
#(user-created subdomain or main domain), not just any domain.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for logic to fetch the vhost name for a given domain.
sub load_ssl_domain_userdata_or_die {
    my ( $user, $domain, $skip_addon_domain_check ) = @_;

    my $file = $domain . '_SSL';

    my $ud_hr = load_userdata( $user, $file, $skip_addon_domain_check );

    if ( !$ud_hr || !%$ud_hr ) {
        die "Failed to load SSL userdata for “$file” ($user)!";
    }

    return $ud_hr;
}

#This is inaccurately named; you actually submit a vhost name
#(user-created subdomain or main domain), not just any domain.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for logic to fetch the vhost name for a given domain.
*load_userdata_domain = *load_userdata;

#Can be called with a parked or addon domain
#(which have no userdata files of their own) -- however, it CANNOT
#be called for auto-created subdomains like “www” or “mail”.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for an implementation that can handle-auto-created domains.
sub load_userdata_real_domain {

    my ( $user, $domain, $userdata ) = @_;
    if ( !$userdata ) {
        $userdata = load_userdata_main($user);
    }
    my $real_domain = get_real_domain( $user, $domain, $userdata );
    return unless $real_domain;

    # set $ADDON_DOMAIN_CHECK_SKIP since we just got the real
    # domain from userdata
    my $userdata_ref = load_userdata( $user, $real_domain, $ADDON_DOMAIN_CHECK_SKIP );
    return wantarray ? ( $userdata_ref, $real_domain ) : $userdata_ref;
}

#“real” domain, in this case, meaning the domain’s Apache vhost’s
#ServerName. Note that this doesn’t grok auto-created subdomains
#like “www” and “mail”.
#See Cpanel::Config::userdata::Utils::get_vhost_name_for_domain()
#for an implementation that can handle-auto-created domains.
sub get_real_domain {
    my ( $user, $domain, $userdata ) = @_;
    if ( !$userdata ) {
        $userdata = load_userdata_main($user);
    }

    # If load_userdata_main fails it returns an empty hashref so
    # we check for existence of main_domain
    return if !$userdata->{'main_domain'};

    return $domain if $domain eq $userdata->{'main_domain'};
    if ( is_parked_domain( $user, $domain, $userdata ) ) {
        return $userdata->{'main_domain'};
    }
    if ( my $sub_domain = is_addon_domain( $user, $domain, $userdata ) ) {
        return $sub_domain;
    }
    return $domain;
}

sub is_parked_domain {

    # See if the domain matches one of the user's parked domains
    my ( $user, $domain, $userdata ) = @_;

    $domain =~ tr{A-Z}{a-z};

    if ( !$userdata ) {
        $userdata = load_userdata_main($user);

        if ( !$userdata || ref $userdata ne 'HASH' ) {
            Cpanel::Debug::log_warn("Failed to load userdata for user '$user'.");
            return 0;
        }
    }

    if ( exists $userdata->{'parked_domains'} && ref $userdata->{'parked_domains'} eq 'ARRAY' ) {
        for my $parked_domain ( @{ $userdata->{'parked_domains'} } ) {
            return 1 if $domain eq $parked_domain;
        }
    }

    return 0;
}

sub is_addon_domain {

    # See if the domain matches one of the user's addon domains;
    # if so, return the subdomain it maps to; otherwise, return undef
    my ( $user, $domain, $userdata ) = @_;

    $domain =~ tr{A-Z}{a-z};

    if ( !$userdata ) {
        $userdata = load_userdata_main($user);

        if ( !$userdata || ref $userdata ne 'HASH' ) {
            Cpanel::Debug::log_warn("Failed to load userdata for user '$user'.");
            return undef;
        }
    }

    if ( exists $userdata->{'addon_domains'} && ref $userdata->{'addon_domains'} eq 'HASH' ) {
        if ( exists $userdata->{'addon_domains'}{$domain} ) {
            return $userdata->{'addon_domains'}{$domain};
        }
    }

    return undef;
}

sub get_domain_type {
    my ( $user, $domain, $userdata ) = @_;

    $domain =~ tr{A-Z}{a-z};

    if ( !$userdata ) {
        $userdata = load_userdata_main($user);

        if ( !$userdata || ref $userdata ne 'HASH' ) {
            Cpanel::Debug::log_warn("Failed to load userdata for user '$user'.");
            return undef;
        }
    }

    return 'main'   if $userdata->{'main_domain'} eq $domain;
    return 'addon'  if $userdata->{'addon_domains'}{$domain};
    return 'parked' if grep { $_ eq $domain } @{ $userdata->{'parked_domains'} };
    return 'sub'    if grep { $_ eq $domain } @{ $userdata->{'sub_domains'} };

    Cpanel::Debug::log_warn("Failed to identify domain type for domain '$domain'.");
    return undef;
}

sub _get_user_files {
    my ($user) = @_;    #We already validated this value.

    die "“$user” has no userdata directory!" if !-d "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user";

    opendir( my $dfh, "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user" ) or do {
        die "userdata opendir($Cpanel::Config::userdata::Constants::USERDATA_DIR/$user): $!\n";
    };

    my @files = grep { !index( $_, '.' ) == 0 } readdir $dfh;

    closedir $dfh or warn "closedir($Cpanel::Config::userdata::Constants::USERDATA_DIR/$user): $!";

    return \@files;
}

#This is inaccurately named: it actually returns SSL *vhost names*,
#not SSL domains.
sub get_ssl_domains {
    my ($user) = @_;

    die "Invalid user: [$user]" if !$user || $user =~ m{\A\.} || $user =~ tr{/}{};

    Cpanel::Context::must_be_list();

    my $ud_main = load_userdata_main($user);

    my %user_files = map { $_ => 1 } @{ _get_user_files($user) };

    # When called with nobody, there may not be a maindomain
    return grep { $user_files{"${_}_SSL"} } (
        $ud_main->{'main_domain'} ? $ud_main->{'main_domain'} : (),
        @{ $ud_main->{'sub_domains'} },
    );
}

#This isn’t very accurately named: it’s actually for a *vhost name*,
#not for a domain.
sub get_userdata_file_for_domain {
    my ( $user, $domain ) = @_;

    _validate_user_and_domain( $user, $domain );

    #Prevent anything from "peeking behind the abstraction".
    die "bad domain “$domain”" if $domain =~ tr{_}{};

    return "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/$domain";
}

#This isn’t very accurately named: it’s actually a check to see if
#a *vhost* has a file in the userdata.
sub user_has_domain {
    my ( $user, $domain ) = @_;

    my $file = get_userdata_file_for_domain( $user, $domain );

    return _file_exists($file);
}

#This isn’t very accurately named: it’s actually a check to see if
#an SSL *vhost* has a file in the userdata.
sub user_has_ssl_domain {
    my ( $user, $domain ) = @_;

    _validate_user_and_domain( $user, $domain );

    return _file_exists("$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/${domain}_SSL");
}

sub _file_exists {
    if ( -e $_[0] ) {
        return 1 if -f _;

        die "“$_[0]” is not a regular file!";
    }
    elsif ( $! != _ENOENT() ) {
        die "stat($_[0]): $!";
    }

    return 0;
}

sub _validate_user_and_domain {
    my ( $user, $domain ) = @_;

    # Note: this function is called over 250k times for a restore
    # with many subdomains, small optimizations matter here.
    # During testing it took the most exclusive time in this module
    if ( !$user ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess('Need username!');
    }
    elsif ( !$domain ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess('Need domain!');
    }
    elsif (index( $user, '.' ) == 0
        || index( $user,   '/' ) > -1
        || index( $domain, '.' ) == 0
        || index( $domain, '/' ) > -1 ) {
        die "Invalid username '$user' ($user) or domain '$domain' ($domain).";
    }

    return;
}

sub _get_domains_key_from_main {
    my ( $user, $key ) = @_;
    my $ud_main = load_userdata_main($user);

    return if !$ud_main;

    return $ud_main->{$key};
}

#Consider the same logic in Cpanel::Config::WebVhosts.
sub get_subdomains {
    my ($user) = @_;

    my $domains_ar = _get_domains_key_from_main( $user, 'sub_domains' );

    return $domains_ar ? [@$domains_ar] : undef;
}

#Consider the same logic in Cpanel::Config::WebVhosts.
sub get_parked_domains {
    my ($user) = @_;

    my $domains_ar = _get_domains_key_from_main( $user, 'parked_domains' );

    return $domains_ar ? [@$domains_ar] : undef;
}

#Consider the same logic in Cpanel::Config::WebVhosts.
sub get_addon_domains {
    my ($user) = @_;

    my $domains_hr = _get_domains_key_from_main( $user, 'addon_domains' );

    return $domains_hr ? [ keys %$domains_hr ] : undef;
}

#Consider the same logic in Cpanel::Config::WebVhosts - all_created_domains()
sub get_all_domains_for_user {
    my ($user) = @_;

    my $ud_main = load_userdata_main($user);

    require Cpanel::Config::userdata::Utils;
    return Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata($ud_main);
}

#Consider the same logic in Cpanel::Config::WebVhosts - all_created_domains_ar()
sub get_all_domains_for_user_ar {
    my ($user) = @_;

    my $ud_main = load_userdata_main($user);

    require Cpanel::Config::userdata::Utils;
    return Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar($ud_main);
}

#Used for tests, to determine when a user has userdata.
#A production user should *always* have userdata.
sub user_exists {
    my ($user) = @_;

    return 0 if !-e "$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user";
    return 1 if -d _;

    die "$user has userdata that isn’t a directory!";
}

sub clear_memory_cache_for_user {
    my ($user) = @_;

    Cpanel::CachedDataStore::clear_one_cache("$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user");

    return;
}

sub clear_memory_cache_for_user_vhost {
    my ( $user, $vhost ) = @_;

    Cpanel::CachedDataStore::clear_one_cache("$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/$vhost");
    Cpanel::CachedDataStore::clear_one_cache("$Cpanel::Config::userdata::Constants::USERDATA_DIR/$user/SSL_$vhost");

    return;
}

1;
