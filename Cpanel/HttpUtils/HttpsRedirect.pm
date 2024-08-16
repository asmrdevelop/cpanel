
# cpanel - Cpanel/HttpUtils/HttpsRedirect.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::HttpUtils::HttpsRedirect;

use strict;
use warnings;

use Cpanel::Result          ();
use Cpanel::AdminBin::Call  ();
use Cpanel::Security::Authz ();

=head1 NAME

Cpanel::HttpUtils::HttpsRedirect

=head1 DESCRIPTION

Determine all sorts of information as to whether https redirects need doing and whether they're done.
Implements the "important bits" of the cPanel API frontend to manage the whole HTTPS redirects for domains feature.

=head1 NOTE TO CALLERS

This uses an adminbin, so only run this as a user.

=head1 VARIABLES

=head2 %ssl_vhosts

Used to keep track of your currently valid SSL domains (this is relatively expensive to get).
Set to undef or empty the array if you want to invalidate this cache.

=cut

our %ssl_vhosts;

=head1 FUNCTIONS

=head2 check_domains_for_https_redirect( STRING $user, ARRAYREF $domains, Cpanel::Result $result, BOOL $do_cert_check )

Use to discover whether a domain EITHER:

    * Has AutoSSL configured for the user passed.
    * Has a currently valid SSL certificate installed for all domains passed.

It is assumed the user owns all passed domains; it is the caller's responsibility to do this check beforehand.
See Cpanel::API::SSL::_filter_domains_by_owner for an example of how to do this.

=head3 Parameters

=over 4

=item B<user> - STRING cPanel username.

=item B<domains> - ARRAYREF of domains to check.  These will be strings.

=item B<result> - Cpanel::Result object.  One will be created for you if you pass [undef].

=item B<do_cert_check> - BOOL. Check whether the certificate is valid or not.  Defaults to true.

=item B<sslstorage> - SSL storage object.  Pass in if you already have one.

=item B<vhost_cache> - Array of vhost hashes ( vhost_name, domain ) as keys

=back

=head3 Returns

Cpanel::Result object.  Check the errors() method returns undef to know whether all domains passed validate, or the user has autossl on.
The errors are messages meant for display to the user, and as such will have to be regexed if you wish to discriminate by domain.

=head3 Termination Conditions

None.

=head3 Notes

This is not intended to be directly used as an API method,
rather it is to be used as a library function by other API modules.

=cut

sub check_domains_for_https_redirect {
    my ( $user, $domains, $result, @extended_options ) = @_;
    my ( $do_cert_check, $sslstorage, $vhost_cache ) = @extended_options;

    $result        //= Cpanel::Result->new();
    $do_cert_check //= 1;

    #XXX if you call this as someone other than $Cpanel::user, you probably can do something naughty
    require Cpanel::Config::userdata::Load unless defined &Cpanel::Config::userdata::Load::user_exists;
    if ( !Cpanel::Config::userdata::Load::user_exists($user) ) {
        $result->error("User provided does not exist");
        return $result;
    }

    #check autoSSL enabled for the user.  If it isn't check the cert is valid.
    eval { Cpanel::Security::Authz::verify_user_has_feature( $user, 'autossl' ) };
    my $had_error = $@;
    if ( $had_error && !$do_cert_check ) {
        $result->error("User provided does not have autossl, and a cert check was not requested.");
        return $result;
    }

    #check cert valid if we are enabling
    if ($do_cert_check) {

        if ($vhost_cache) {

            #XXX adminbin's serializer chokes after about 100 records, so we have to batch this unfortunately.
            while ( ref $vhost_cache eq 'ARRAY' && scalar(@$vhost_cache) ) {
                my @vhost_batch = splice( @$vhost_cache, 0, 100 );
                my %ssl_batch   = Cpanel::AdminBin::Call::call( "Cpanel", "ssl_call", "GET_SSL_VHOSTS", \@vhost_batch );
                foreach my $key ( keys(%ssl_batch) ) {
                    $ssl_vhosts{$key} = $ssl_batch{$key};
                }
            }
        }
        else {
            %ssl_vhosts = Cpanel::AdminBin::Call::call( "Cpanel", "ssl_call", "GET_SSL_VHOSTS" ) unless %ssl_vhosts;
        }

        foreach my $domain (@$domains) {
            $result->error( "No Valid SSL certificate appears to exist for “[_1]”. ", $domain ) unless exists $ssl_vhosts{$domain};
            $result->error( "Invalid SSL certificate installed on “[_1]”. ",          $domain ) unless $ssl_vhosts{$domain}->{ssl_valid};
            $result->message( "Some aliases of domain “[_1]” do not have valid SSL.", $domain ) unless $ssl_vhosts{$domain}->{all_aliases_valid};
        }
    }
    return $result;
}

=head2 get_userdata_with_https_redirect_info(STRING domain, STRING user, HASHREF data)

Convenience method used in various APIs to set the can_https_redirect and is_https_redirecting fields in the returned [data] hashref.
This is modified by reference.

=head3 Returns

1

=head3 Termination conditions

Will throw if you can't load main userdata, but you're probably already dead if you are calling this.

=cut

sub get_userdata_with_https_redirect_info {
    my ( $domain, $user, $data, $vhost_cache ) = @_;

    my $real_domain = $domain;

    #Then I need to set can_https_redirect and is_https_redirecting
    require Whostmgr::Transfers::ConvertAddon::Utils;
    $Whostmgr::Transfers::ConvertAddon::Utils::do_domain_caching = 1;

    #XXX some addon domains can get created which have no vhost config file in /var/cpanel/userdata somehow.  This breaks in that case.
    #We won't be able to get the info as to it's owning subdomain in that case, but we won't be able to act on it anyways due to no file.
    my $serveralias = eval { Whostmgr::Transfers::ConvertAddon::Utils::get_addon_domain_details( $domain, { hasroot => 0 } ) };
    $real_domain = $serveralias->{subdomain} if ref $serveralias eq "HASH";
    my $udata = $data;
    $udata = Cpanel::Config::userdata::Load::load_userdata( $user, $real_domain ) if $real_domain ne $domain;

    my $result = Cpanel::HttpUtils::HttpsRedirect::check_domains_for_https_redirect( $user, [$domain], undef, undef, undef, $vhost_cache );

    $data->{'all_aliases_valid'}    = ref( $result->messages() ) ne 'ARRAY';
    $data->{'can_https_redirect'}   = ref( $result->errors() ) ne 'ARRAY';
    $data->{'is_https_redirecting'} = $udata->{ssl_redirect};
    return 1;
}

1;

__END__
