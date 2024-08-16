package Whostmgr::API::1::Utils::Execute;

# cpanel - Whostmgr/API/1/Utils/Execute.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Execute

=head1 SYNOPSIS

    $result = Whostmgr::API::1::Utils::Execute::execute_or_die(
        APIModule => 'funcname',
        { arg1 => 'val1', .. },
        \%meta_arguments,
    );

=head1 DESCRIPTION

This module provides a simple interface for calling WHM API v1 functions
from Perl.

=cut

#----------------------------------------------------------------------

use Cpanel::APICommon::Args ();
use Cpanel::Exception       ();
use Cpanel::LoadModule      ();

use Whostmgr::API::1::Data::Wrapper ();
use Whostmgr::API::1::Utils::Result ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $result = execute_or_die( $MODULE, $NAME, \%ARGS, \%META_ARGS )

Calls a WHM API v1 function and returns the result. If the API indicates
a failure, a L<Cpanel::Exception::API::WHM1> instance is thrown.

$MODULE and $NAME indicate the function call, e.g.,
( C<Accounts>, C<listaccts> ).

%ARGS are the key/value pairs that go into the function. Values may
be scalars or, as a convenience, array references. Array references will
be unrolled as per C<Cpanel::APICommon::Args::expand_array_refs()> prior
to being given to the API call.

%META_ARGS is given to C<Whostmgr::API::1::Data::Args::build_api_args()>,
to harness the API’s post-process functionality (e.g.,
sort/filter/paginate). See that function for the format of this hash.

The return is a L<Whostmgr::API::1::Utils::Result> instance.

=cut

sub execute_or_die ( $module, $func_name, $args_hr = undef, $meta_hr = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my $result = execute( $module, $func_name, $args_hr, $meta_hr );

    if ( $result->get_error() ) {
        die Cpanel::Exception::create(
            'API::WHM1',
            [
                function_name => $func_name,
                result        => $result,
            ]
        );
    }

    return $result;
}

=head2 $result = execute( .. )

This accepts the same arguments as C<execute_or_die()>. The difference
is that this will B<NOT> throw an exception if the API call indicates
failure.

(It I<will> still throw if the API call doesn’t exist.)

=cut

sub execute ( $module, $func_name, $args_hr = undef, $meta_hr = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    my $full_module = "Whostmgr::API::1::$module";
    Cpanel::LoadModule::load_perl_module($full_module);

    my $cr = $full_module->can($func_name) or die "Missing API call: ${module}::$func_name!";

    $args_hr = Cpanel::APICommon::Args::expand_array_refs($args_hr);

    my $resp_hr = Whostmgr::API::1::Data::Wrapper::execute(
        $meta_hr,
        undef,
        sub {
            my ( $metadata, undef, $api_args_hr ) = @_;
            return $cr->( $args_hr, $metadata, $api_args_hr );
        },
        0,
    );

    # For some reason Wrapper::execute() assigns “Direct” as the value
    # here. Make it the function name in order to match bin/whmapi1.
    $resp_hr->{'metadata'}{'command'} = $func_name;

    return Whostmgr::API::1::Utils::Result->new($resp_hr);
}

1;
