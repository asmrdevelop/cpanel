package Whostmgr::API::1::Utils::Proxy;

# cpanel - Whostmgr/API/1/Utils/Proxy.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Proxy

=head1 SYNOPSIS

    $result = Whostmgr::API::1::Utils::Proxy::proxy_if_configured(
        perl_arguments -> [ $args, $metadata, $api_args ],
        worker_type => 'Mail',
        account_name => 'cpusername',
    );

=head1 DESCRIPTION

This function facilitates relatively easy proxying of WHM API calls
to worker (e.g., C<Mail>) nodes.

=cut

#----------------------------------------------------------------------

use Cpanel::Caller::Function            ();
use Cpanel::Config::LoadCpUserFile      ();
use Cpanel::LinkedNode::RemoteAPI       ();
use Cpanel::LinkedNode::Worker::Storage ();
use Cpanel::Exception                   ();
use Whostmgr::API::1::Data::Args        ();
use Whostmgr::API::1::Data::Filter      ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $result = proxy_if_configured( %OPTS )

Proxies an API call if indicated.

%OPTS are:

=over

=item * C<function> - Optional, defaults to the nearest function name in the
call stack that does not begin with an underscore (C<_>).

=item * C<perl_arguments> - Array ref of arguments given to the
perl function that implements the API call.

=item * C<worker_type> - The type of worker node (e.g., C<Mail>) to look up.

=item * C<account_name> - Either the name of a cPanel user or a Webmail user.

=back

To determine if an API call proxy is indicated, this determines the cPanel
user from the C<account_name> then determines whether that cPanel user is
configured with a worker node of type C<worker_type>. If so, the API call is
proxied to the worker node.

When an API call is proxied, the remote API call response’s metadata is
copied into C<metadata>.

=head3 RETURN VALUE

When an API call is proxied, this returns a
L<Whostmgr::API::1::Utils::Result> instance that represents the remote
API call response.

When no proxying happens, this returns undef.

=cut

sub proxy_if_configured (%opts) {
    my ( $fn, $perl_args, $worker_type, $account_name ) = @opts{ 'function', 'perl_arguments', 'worker_type', 'account_name' };

    $fn ||= Cpanel::Caller::Function::get_latest_public();

    my $cpusername;

    if ( -1 == index( $account_name, '@' ) ) {
        $cpusername = $account_name;
    }
    else {
        require Cpanel::AcctUtils::Lookup;
        $cpusername = Cpanel::AcctUtils::Lookup::get_system_user($account_name);

        if ( !$cpusername ) {

            # Does this need to be translated?
            die Cpanel::Exception->create_raw("“$account_name” has no owner!");
        }
    }

    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load_or_die($cpusername);

    my $result;

    my $alias_tk_ar = Cpanel::LinkedNode::Worker::Storage::read( $cpuser_hr, $worker_type );
    if ($alias_tk_ar) {
        my $alias = $alias_tk_ar->[0];

        my $api = Cpanel::LinkedNode::RemoteAPI::create_whmapi1($alias);

        my ( $args, $metadata, $api_args ) = @$perl_args;

        my %args_copy = %$args;
        Whostmgr::API::1::Data::Args::insert_api_args( $api_args, \%args_copy );

        $result = $api->request_whmapi1( $fn, \%args_copy );

        $result->export_metadata($metadata);

        $metadata->{'proxied_from'} = [
            $api->get_hostname(),
            $result->get_proxied_from(),
        ];

        if ( $api_args->{'filter'} ) {
            Whostmgr::API::1::Data::Filter::mark_filters_done(
                $api_args->{'filter'},
                Whostmgr::API::1::Data::Filter::get_filters($api_args),
            );
        }

        $metadata->{'__chunked'} = 1 if $api_args->{'chunk'} && $api_args->{'chunk'}{'enable'};

        if ( my $sort_hr = $api_args->{'sort'} ) {
            for my $fieldspec ( keys %$sort_hr ) {
                next if $fieldspec eq 'enable';
                $sort_hr->{$fieldspec}{'__done'} = 1;
            }
        }
    }

    return $result;
}

1;
