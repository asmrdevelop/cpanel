#  Copyright 1999-2021. Plesk International GmbH. All rights reserved.

package Cpanel::API::WpToolkitCli;

use cPstrict;

our $VERSION = '1.1';

use Cpanel::AdminBin::Call  ();
use Cpanel::Binaries        ();
use Cpanel::JSON            ();
use Cpanel::SafeRun::Object ();

use Try::Tiny;

sub execute_command ( $args, $result ) {

    if ( $> == 0 ) {
        return _execute_command_as_root( $args, $result );
    }

    my $isSuccess = 0;
    try {
        if ( !main::hasfeature('wp-toolkit') ) {
            die "Access denied! You don't have permission \"wp-toolkit\".";
        }

        my $command     = $args->get_required('command');
        my @params      = $args->get_multiple('command-param');
        my @commandArgs = ( $command, @params );

        my ( $stdout, $stderr, $exitCode ) = Cpanel::AdminBin::Call::call(
            "Cpanel",
            "WpToolkitCli",
            "execute_command",
            @commandArgs
        );

        if ( $exitCode == 0 ) {

            # Success
            # decode_json throw error if $stdout cannot be parsed as JSON
            $result->data( Cpanel::JSON::Load( $stdout) );
            $isSuccess = 1;

        }
        elsif ( $exitCode == 256 ) {

            # Has returned result of --help command
            $result->error('Command does not exist.');

        }
        else {
            # Message will be in $stdout or $stderr
            $result->error( $stdout . $stderr );
        }
    }
    catch {
        my $e = $_;
        if ( $e->can("to_string") ) {
            $result->error( $e->to_string() );
        }
        else {
            $result->error($e);
        }
    };

    return $isSuccess;
}

sub _execute_command_as_root ( $args, $results ) {

    my $command = $args->get_required('command');
    my @params  = $args->get_multiple('command-param');
    my $format  = $args->get('format') // 'json';         # default to json when not provided

    my $isSuccess = 0;

    try {

        my $run = Cpanel::SafeRun::Object->new_or_die(
            program => Cpanel::Binaries::path('wp-toolkit'),
            args    => [
                $command,                                   #
                $format ? ( '-format' => $format ) : (),    # format can be unsupported for some actions
                @params,                                    #
            ],
        );

        my $data = eval { Cpanel::JSON::Load( $run->stdout() ) } // $run->stdout();
        $results->data($data);

        $isSuccess = 1;

    }
    catch {
        my $e = $_;
        $results->error(qq[Error while running CLI command $command: $e]);
    };

    return $isSuccess;
}

1;
