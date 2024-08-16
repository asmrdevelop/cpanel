
# cpanel - Cpanel/ApiUtils/Execute.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ApiUtils::Execute;

use strict;
use Cpanel::Locale::Lazy 'lh';
use Cpanel::SafeRun::Object ();
use Cpanel::JSON            ();

=head1 NAME

Cpanel::ApiUtils::Execute

=head1 FUNCTIONS

=head2 externally_as_user(CPUSER, MODULE, FUNCTION, FUNC_PARAMS_HR)

Executes UAPI function FUNCTION from module MODULE (without Cpanel:: prefix) as
cPanel user CPUSER. FUNC_PARAMS_HR is an optional hash ref of parameters to the
API function.

Returns a plain hash ref (not an object) of the decoded response from bin/uapi.

From the caller's perspective, this is similar in purpose to Cpanel::API::execute,
but internally it functions differently. Whereas Cpanel::API::execute relies on
the ability to load the API implementation module (e.g., Cpanel::API::Email)
into the same process as a Perl module, externally_as_user() relies entirely on
the UAPI binary. This adds some overhead to the process, but it brings the
benefit of allowing you to execute API functions from unshipped modules without
having to precompile them into your binary.

=cut

sub externally_as_user {
    my ( $user, $mod, $func, $func_params ) = @_;

    $func_params ||= {};

    my @uapi_args = ( '--output=json', "--user=$user", $mod, $func );
    for my $k ( sort keys %$func_params ) {
        push @uapi_args, "$k=$func_params->{$k}";
    }

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => _uapi_bin(),
        args    => \@uapi_args,
    );

    my $output_sr = $run->stdout_r;

    my $loaded = Cpanel::JSON::Load($$output_sr);

    if ( !$loaded->{result}{status} ) {
        die join( "\n", @{ $loaded->{result}{errors} } ) . "\n";
    }

    return $loaded;
}

sub _uapi_bin {
    return '/usr/local/cpanel/bin/uapi';
}

1;
