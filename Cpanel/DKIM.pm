package Cpanel::DKIM;

# cpanel - Cpanel/DKIM.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles                  ();
use Cpanel::DKIM::Save                   ();
use Cpanel::DKIM::Load                   ();
use Cpanel::LoadFile                     ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();

our $DKIM_SELECTOR = 'default._domainkey.';

# TODO: Move this closer to the cpuser datastore. It isn’t DKIM logic.
sub get_all_domains_ref {
    my ($user) = @_;
    my @DOMAINS;

    require Cpanel::Config::HasCpUserFile;
    require Cpanel::Config::LoadCpUserFile;
    return \@DOMAINS unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    if ( scalar keys %{$cpuser_ref} ) {
        if ( $cpuser_ref->{'DOMAIN'} ) { push @DOMAINS, $cpuser_ref->{'DOMAIN'} }
        if ( ref $cpuser_ref->{'DOMAINS'} eq 'ARRAY' ) {
            push @DOMAINS, @{ $cpuser_ref->{'DOMAINS'} };
        }
    }

    @DOMAINS = grep( !m/\*/, @DOMAINS );

    return \@DOMAINS;
}

# XXX Do not use this function directly.
# Use Cpanel::DKIM::Transaction instead.
sub remove_user_domain_keys {
    my %OPTS = @_;

    my ( $status, $msg, $state_hr ) = setup_domain_keys( 'user' => $OPTS{'user'}, 'delete' => 1, 'skipreload' => ( $OPTS{'skipreload'} ? 1 : 0 ) );

    # NB: This will remove all of the user’s domains’ keys regardless
    # of whether DNS update failed for any of the domains.
    if ($status) {
        my $all_domains_ref = get_all_domains_ref( $OPTS{'user'} );
        check_and_remove_keys( $all_domains_ref, $OPTS{'user'} );
    }

    return ( $status, $msg, $state_hr );
}

sub has_dkim {
    my %OPTS = @_;

    my $user;
    if ( exists $OPTS{'user'} ) {
        $user = $OPTS{'user'};
    }
    elsif ( exists $OPTS{'domain'} ) {
        $user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $OPTS{'domain'}, { 'default' => undef } );
    }

    if ($user) {
        return 1 if $user eq 'root';
    }
    elsif ( $OPTS{'domain'} ) {
        require Cpanel::Hostname;
        return 1 if $OPTS{'domain'} eq Cpanel::Hostname::gethostname();
    }
    require Cpanel::Config::HasCpUserFile;
    require Cpanel::Config::LoadCpUserFile;
    return 0 unless ( $user && Cpanel::Config::HasCpUserFile::has_cpuser_file($user) );
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

    if ( !UNIVERSAL::isa( $cpuser_ref, 'HASH' ) ) {
        return 0;
    }

    return $cpuser_ref->{'HASDKIM'} ? 1 : 0;
}

#----------------------------------------------------------------------
# This will set up the filesystem, but only if “delete” is not passed.
#
# XXX Do not use this function directly.
# Use Cpanel::DKIM::Transaction instead.
sub setup_domain_keys {
    my %OPTS       = @_;
    my $delete     = $OPTS{'delete'};
    my $skipreload = $OPTS{'skipreload'} ? 1 : 0;
    my $parent     = $OPTS{'parent'};
    my $zone_ref   = $OPTS{'zone_ref'};             # Allow passing in the hashref in the format Cpanel::DnsUtils::Fetch returns

    # user or domain to find domains
    # delete to delete found domains

    if ( !mta_has_dkim() ) {
        return ( 0, _locale()->maketext('The MTA does not support DKIM.') );
    }

    my $domains_ref;
    if ( exists $OPTS{'domains_ar'} && !$OPTS{'user'} ) {
        return ( 0, "You must specify “user” when the “domains_ar” is specified." );
    }
    elsif ( exists $OPTS{'domain'} && ( $delete || has_dkim( 'domain' => $OPTS{'domain'} ) ) ) {
        $domains_ref = [ $OPTS{'domain'} ];
    }
    elsif ( exists $OPTS{'user'} && ( $delete || has_dkim( 'user' => $OPTS{'user'} ) ) ) {
        $domains_ref = $OPTS{'domains_ar'} ? $OPTS{'domains_ar'} : get_all_domains_ref( $OPTS{'user'} );
    }
    else {
        my $msg;
        if ( exists $OPTS{'domain'} ) {
            $msg = _locale()->maketext( 'DKIM is not enabled for [_1].', $OPTS{'domain'} );
        }
        elsif ( exists $OPTS{'user'} ) {
            $msg = _locale()->maketext( 'DKIM is not enabled for [_1].', $OPTS{'user'} );
        }
        else {
            $msg = _locale()->maketext('No user or domain is specified.');
        }
        return ( 0, $msg );
    }

    # Silently discard wildcards as dns does
    # not support this.
    @{$domains_ref} = grep { index( $_, '*' ) == -1 } @{$domains_ref};

    _check_and_gen_keys($domains_ref);

    my @installlist;
    foreach my $domain ( @{$domains_ref} ) {
        my $record = _fetch_public_key_as_dns_record($domain);
        push @installlist, {
            'record' => $DKIM_SELECTOR . $domain,
            'domain' => $domain,
            'value'  => $record,
            'zone'   => $parent                     # may be undef; defaulted later
        };
        if ($delete) {
            my $alt_record = $record;
            $alt_record =~ s/v=DKIM1;\s+//;
            push @installlist, {
                'record' => $DKIM_SELECTOR . $domain,
                'domain' => $domain,
                'value'  => $alt_record,
                'zone'   => $parent                     # may be undef; defaulted later
            };
        }
    }

    require Cpanel::DnsUtils::Install;
    return Cpanel::DnsUtils::Install::install_txt_records( \@installlist, $domains_ref, $delete, $skipreload, $zone_ref );
}

sub _fetch_public_key_as_dns_record {
    my $domain  = shift;
    my $keydata = get_domain_public_key($domain);
    require Cpanel::PEM;
    my $key = Cpanel::PEM::strip_pem_formatting($keydata);
    return generate_dkim_record_rdata($key);
}

sub generate_dkim_record_rdata {
    my ($key) = @_;
    return 'v=DKIM1; k=rsa; p=' . $key . ';';
}

# ensure_dkim_keys_exist
#
# This function returns an arrayref of hashrefs in the
# following format:
#
#   [
#        {'status'=>0,'domain'=>'domain.tld','msg'=>'A message'},
#        {'status'=>1,'domain'=>'domain2.tld','msg'=>'A message'},
#        ....
#   ]
#
#
sub ensure_dkim_keys_exist {
    my ($domains_ref) = @_;

    return _check_and_gen_keys($domains_ref);
}

sub check_and_remove_keys {
    my $domain_ref = shift;
    my $username   = shift or die 'need username';

    foreach my $domain ( @{$domain_ref} ) {
        Cpanel::DKIM::Save::delete( $domain, $username );
    }
    return;
}

sub _check_and_gen_keys {
    my $domain_ref = shift;

    setup_file_stores();
    require Cpanel::OpenSSL;
    my $openssl = Cpanel::OpenSSL->new();

    my $keysize_min = $Cpanel::OpenSSL::DEFAULT_KEY_SIZE;
    my @status;

    foreach my $domain ( @{$domain_ref} ) {
        my ( $private, $public ) = map { "$Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT/$_/$domain" } ( 'private', 'public' );
        my $has_existing_private_key = 0;
        my $has_existing_public_key  = 0;
        my $private_key;
        if ( -s $private ) {
            $has_existing_private_key = 1;

            # TODO: in the future we will need to support ECC keys which will
            # have to do a better “encryption strength liabilities” check then
            # a simple key size
            my $key_size = $openssl->get_key_size( keyfile => $private );
            if ( $key_size && $key_size >= $keysize_min ) {
                if ( -s $public ) {
                    $has_existing_public_key = 1;
                    push @status, { 'domain' => $domain, 'status' => 1, 'msg' => 'key is acceptable' };
                    next;
                }

                # The public_key is missing and the private key is acceptable
                require Cpanel::LoadFile;
                $private_key = Cpanel::LoadFile::loadfile($private);
            }
        }

        if ( !$private_key ) {
            my $gen_private = $openssl->generate_key();
            if ( !$gen_private->{'status'} ) {
                warn $gen_private->{'message'};
                push @status, { 'domain' => $domain, 'status' => 0, 'msg' => $gen_private->{'message'} };
                next;
            }
            $private_key = $gen_private->{'stdout'};
        }

        my $ok = eval {
            Cpanel::DKIM::Save::save( $domain, $private_key );
            1;
        };

        if ( !$ok ) {
            my $err = $@;
            warn $err;
            push @status, { 'domain' => $domain, 'status' => 0, 'msg' => $err };
            next;
        }

        push @status, { 'domain' => $domain, 'status' => 1, 'msg' => ( ( $has_existing_private_key && $has_existing_public_key ) ? 'replaced key' : $has_existing_private_key ? 'recreated public key' : 'created new key' ) };

    }

    return \@status;
}

# XXX Avoid use of this function in new code.
# Use Cpanel::DKIM::Load instead.
sub get_domain_private_key {
    my $domain = shift;
    $domain =~ tr{/}{}d;    # TODO: this should die in the future
    return Cpanel::LoadFile::loadfile( _get_key_path( "private", $domain ) );
}

sub get_domain_public_key {
    my $domain = shift;
    $domain =~ tr{/}{}d;    # TODO: this should die in the future
    return Cpanel::LoadFile::loadfile( _get_key_path( "public", $domain ) );
}

# $type should be either public or private.
# accessed from tests
*_get_key_path = *Cpanel::DKIM::Load::get_key_path;

sub install_dkim_key_for_domain {
    my ( $domain, $private_key_text ) = @_;

    Cpanel::DKIM::Save::save( $domain, $private_key_text );

    return 1;
}

# make any test easier
sub _root_dir {
    return $Cpanel::ConfigFiles::DOMAIN_KEYS_ROOT;
}

sub setup_file_stores {
    my $dk_root = _root_dir();

    my @dirs = (

        # root need to be first ( args to use with check_and_fix_owner_and_permissions_for )
        { path => $dk_root,              uid => 0, gid   => 0,      octal_perms => 0755 },
        { path => $dk_root . '/public',  uid => 0, group => 0,      octal_perms => 0711 },
        { path => $dk_root . '/private', uid => 0, group => 'mail', octal_perms => 0750 },
    );

    require Cpanel::FileUtils::Chown;

    map {
        my $opts = $_;

        # create directory if missing
        mkdir( $opts->{path}, $opts->{octal_perms} ) unless -d $opts->{path};

        # always do this check to autofix any problem introduced
        #   during a previous migration or any other source
        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(%$opts);
    } @dirs;

    return;
}

sub mta_has_dkim {
    return 1;
}

my $locale;

sub _locale {
    return $locale if $locale;
    require Cpanel::Locale;
    $locale = Cpanel::Locale->get_handle();
    return $locale;
}
1;
