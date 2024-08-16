package Whostmgr::API::1::UserDomains;

# cpanel - Whostmgr/API/1/UserDomains.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::UserDomains

=head1 DESCRIPTION

This module contains interfaces to user domains for WHM API v1.

=cut

#----------------------------------------------------------------------

use Cpanel::APICommon::Persona ();
use Cpanel::Exception          ();
use Whostmgr::API::1::Utils    ();

#----------------------------------------------------------------------

use constant ARGUMENT_NEEDS_PARENT => {
    create_parked_domain_for_user => 'username',
};

use constant NEEDS_ROLE => {
    create_parked_domain_for_user                  => undef,
    create_subdomain                               => undef,
    updateuserdomains                              => undef,
    delete_domain                                  => undef,
    PRIVATE_create_parked_domain_for_user_on_child => undef,
};

=head1 FUNCTIONS

=head2 create_parked_domain_for_user

Arguments:

=over

=item * C<username>

=item * C<domain> - The new domain name to create.

=item * C<web_vhost_domain> - An existing domain on the web vhost
to which the new domain name should be added. Note that if this is
not the cPanel account’s main domain, then the new domain will be
considered an “addon” domain.

=back

=cut

sub create_parked_domain_for_user ( $args_hr, $metadata, @ ) {
    return _create_parked_domain_for_user( $args_hr, $metadata );
}

sub _create_parked_domain_for_user ( $args_hr, $metadata, %xtra_parkadmin_args ) {    ## no critic qw(ProhibitManyArgs) - mis-parse

    my $username         = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'username' );
    my $domain           = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'domain' );
    my $web_vhost_domain = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'web_vhost_domain' );

    require Cpanel::Validate::Username;
    require Cpanel::Validate::Domain;

    Cpanel::Validate::Username::validate_or_die($username);
    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($domain);
    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($web_vhost_domain);

    require Cpanel::Config::WebVhosts;
    my $wvh    = Cpanel::Config::WebVhosts->load($username);
    my $vhname = $wvh->get_vhost_name_for_domain($web_vhost_domain);

    if ( !$vhname ) {
        die Cpanel::Exception->create( "“[_1]” does not refer to any of “[_2]”’s web virtual hosts.", [ $web_vhost_domain, $username ] );
    }

    require Whostmgr::ACLS;
    if ( !Whostmgr::ACLS::hasroot() ) {

        require Whostmgr::AcctInfo::Owner;

        # If we are not root, we must be the user or own the user
        if ( $ENV{'REMOTE_USER'} ne $username
            && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $username ) ) {

            die Cpanel::Exception->create(
                "The user “[_1]” does not have access to the account “[_2]”.",
                [ $ENV{'REMOTE_USER'}, $username ]
            );
        }

        require Cpanel::Sys::Hostname;
        require Whostmgr::Func;

        if ( Whostmgr::Func::is_subdomain_of_domain( Cpanel::Sys::Hostname::gethostname(), $domain ) ) {

            require Cpanel::Config::LoadCpConf;
            if ( !Cpanel::Config::LoadCpConf::loadcpconf()->{'allowresellershostnamedomainsubdomains'} ) {

                die Cpanel::Exception->create("Resellers do not have the necessary permissions to create subdomains of the server’s main domain.");
            }
        }

    }

    require Cpanel::ParkAdmin;
    my ( $ok, $err ) = Cpanel::ParkAdmin::park(
        user      => $username,
        newdomain => $domain,
        domain    => $vhname,
        %xtra_parkadmin_args,
    );

    die Cpanel::Exception->create_raw($err) if !$ok;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return undef;
}

#----------------------------------------------------------------------

=head2 PRIVATE_create_parked_domain_for_user_on_child

Same as C<create_parked_domain_for_user()> but ignores certain elements
of the local configuration that may differ from the parent node’s. This
is what the parent node should call to propagate domain creation to the
child node.

=cut

sub PRIVATE_create_parked_domain_for_user_on_child ( $args, $metadata, @ ) {
    return _create_parked_domain_for_user(
        $args, $metadata,

        # Prevent failure when, e.g., the parent allows remote or
        # unregistered domains but the child doesn’t.
        domain_registration_validation => 'none',
    );
}

#----------------------------------------------------------------------

=head2 delete_domain

L<https://go.cpanel.net/whm_delete_domain>

=cut

sub delete_domain ( $args_hr, $metadata, $api_info_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'domain' );

    require Cpanel::AcctUtils::DomainOwner::Tiny;
    my $username = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => undef } );

    my $domain_type;

    if ($username) {
        my ( $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $api_info_hr->{'persona'}, $username );

        if ($str) {
            $metadata->set_not_ok($str);
            return $err_obj;
        }

        require Cpanel::Config::WebVhosts;
        my $wvh = Cpanel::Config::WebVhosts->load($username);

        if ( $domain eq $wvh->main_domain() ) {
            die Cpanel::Exception->create_raw("“$domain” is “$username”’s main domain!");
        }

        my $park_parent;

        my $is_parked = grep { $_ eq $domain } $wvh->parked_domains();

        if ($is_parked) {
            $domain_type = 'parked';
            $park_parent = $wvh->main_domain;
        }
        else {
            $park_parent = !$is_parked && { $wvh->addon_domains() }->{$domain};
        }

        if ($park_parent) {
            $domain_type ||= 'addon';

            require Cpanel::ParkAdmin;

            my ( $ok, $err ) = Cpanel::ParkAdmin::unpark(
                user          => $username,
                domain        => $domain,
                parent_domain => $park_parent,
            );

            die Cpanel::Exception->create_raw($err) if !$ok;
        }
        elsif ( grep { $_ eq $domain } $wvh->subdomains() ) {
            $domain_type = 'sub';

            _delsubdomain( $username, $domain );
        }
        else {
            warn "getdomainowner() reports that “$username” owns “$domain”, but that domain doesn’t appear in “$username”’s web vhost configuration. Possible cache expiration bug.";
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        username => $username,
        type     => $domain_type,
    };
}

sub _delsubdomain ( $username, $domain ) {
    require Cpanel::Sub;

    # NB: Even if the subdomain is >1 label deeper than
    # its “true” parent domain, delsubdomain() will sort out
    # the difference.

    $domain =~ m<\A([^.]+)\.(.+)> or do {
        die "Failed to split domain “$domain”!";
    };

    my ( $leaf_label, $parent_domain ) = ( $1, $2 );

    my ( $ok, $err ) = Cpanel::Sub::delsubdomain(
        user       => $username,
        subdomain  => $leaf_label,
        rootdomain => $parent_domain,
    );

    die Cpanel::Exception->create_raw("delete “$domain”: $err") if !$ok;

    return;
}

sub updateuserdomains {
    my ( $args_hr, $metadata ) = @_;

    require Cpanel::Userdomains;
    Cpanel::Userdomains::updateuserdomains();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub create_subdomain ( $args_hr, $metadata, $api_info_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $domain = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'domain' );

    my $username;

    if ( $username = _getdomainowner($domain) ) {
        die "“$username” already controls “$domain”!";
    }

    # NB: The actual leaf labels & parent domain don’t matter
    # because addsubdomain() will figure out what the “real”
    # parent domain is and adjust accordingly.

    ( $username, my $leaf_part, my $parent_domain ) = _get_username_and_domain_split_for_new_subdomain($domain);

    my ( $str, $err_obj ) = Cpanel::APICommon::Persona::get_whm_expect_parent_error_pieces( $api_info_hr->{'persona'}, $username );

    if ($str) {
        $metadata->set_not_ok($str);
        return $err_obj;
    }

    my $docroot = Whostmgr::API::1::Utils::get_length_required_argument( $args_hr, 'document_root' );

    require Cpanel::Validate::DocumentRoot;
    Cpanel::Validate::DocumentRoot::validate_subdomain_document_root_or_die($docroot);

    my $use_canonical_name = !!$args_hr->{'use_canonical_name'};

    require Cpanel::SubDomain::Create;
    my ( $ok, $err ) = Cpanel::SubDomain::Create::create_with_phpfpm_setup(
        $leaf_part,
        $parent_domain,
        user              => $username,
        usecannameoff     => !$use_canonical_name,
        documentroot      => $docroot,
        skip_conf_rebuild => 0,
    );

    die Cpanel::Exception->create_raw($err) if !$ok;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        username => $username,
    };
}

sub _get_username_and_domain_split_for_new_subdomain ($domain) {
    my @pieces = split m<\.>, $domain;

    my $username;
    my $parent_domain;
    my @leaf_pieces;

    while ( @pieces > 2 ) {
        push @leaf_pieces, shift @pieces;

        $parent_domain = join( '.', @pieces );

        last if $username = _getdomainowner($parent_domain);
    }

    if ( !$username ) {
        die Cpanel::Exception->create( "No user on this system owns a parent domain of “[_1]”.", [$domain] );
    }

    return ( $username, join( '.', @leaf_pieces ), $parent_domain );
}

sub _getdomainowner ($domain) {
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { default => undef } );
}

1;
