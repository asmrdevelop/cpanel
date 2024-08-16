package Cpanel::API::Batch;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use strict;
use warnings;

use Cwd ();

use Cpanel            ();
use Cpanel::API       ();
use Cpanel::Exception ();
use Cpanel::JSON      ();
use Umask::Local      ();

my @STRINGENCE_EXCEPTIONS = (

    #Legacy CJT (and, apparently, new CJT as well) included this to work
    #around an IE6 caching problem. This has probably long ceased to be needed
    #(cf. https://webpros.atlassian.net/browse/UI-126), so hopefully we can remove
    #it; in the meantime, this allows our old JS client code to do batch mode.
    'cache-fix',
    'cpanel_jsonapi_func',
    'cpanel_jsonapi_module',
    'cpanel_jsonapi_apiversion',
    'api.version',
    'api.persona',
);

sub _additional_stringence {
    my ($args) = @_;

    my %stringence_lookup = map { $_ => 1 } @STRINGENCE_EXCEPTIONS;

    #NOTE: duplicated w/ Cpanel/Args.pm
    my @invalid = grep { !$stringence_lookup{$_} && !m<\Acommand(?:-[0-9]+)?\z> } $args->keys();

    if (@invalid) {
        die Cpanel::Exception::create( 'InvalidParameter', "The following parameter [numerate,_1,name is,names are] invalid: [join,~, ,_2]", [ scalar(@invalid), \@invalid ] );
    }

    return;
}

sub _get_commands_from_args_object {
    my ($args) = @_;

    _additional_stringence($args);

    my @commands = $args->get_length_required_multiple('command');

    for my $c ( 0 .. $#commands ) {
        my $decoded = Cpanel::JSON::Load( $commands[$c] );
        if ( 'ARRAY' ne ref $decoded ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following “[_1]” is not an array: [_2]', [ 'command', $commands[$c] ] );
        }

        if ( !$decoded->[0] ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following “[_1]” lacks a module: [_2]', [ 'command', $commands[$c] ] );
        }

        if ( !$decoded->[1] ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following “[_1]” lacks a function: [_2]', [ 'command', $commands[$c] ] );
        }

        if ( ( @$decoded > 2 ) && 'HASH' ne ref $decoded->[2] ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following “[_1]”’s arguments are not given as a hash: [_2]', [ 'command', $commands[$c] ] );
        }

        if ( @$decoded > 3 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The following “[_1]” has too many array members: [_2]', [ 'command', $commands[$c] ] );
        }

        $commands[$c] = $decoded;    #don’t need the JSON anymore
    }

    return @commands;
}

#Bail out at the first sign of failure.
#(Would there be virtue in a non-strict, fail_ok() function??)
sub strict {
    my ( $args, $result ) = @_;

    return _do_batch(
        $args, $result,
        sub {
            my ( $c, $result ) = @_;
            die Cpanel::Exception->create( 'Command #[numf,_1] failed. It reported the following error: [_2]', [ $c, $result->errors_as_string() ] );
        },
    );
}

sub _do_batch {
    my ( $args, $result, $error_handler_cr ) = @_;

    my @commands = _get_commands_from_args_object($args);

    #Ensure that everything we mean to call actually exists.
    Cpanel::API::get_coderef(@$_) for @commands;

    my @batch_response;
    $result->data( \@batch_response );

    #NOTE: We need to reset the environment for each individual command
    #so that no one command (inadvertently?) influences another.
    #Strictly speaking, the only reliable way to do that is to fork()
    #for each call, but that would be prohibitively slow. (cf. CPANEL-2168)

    my $cwd = Cwd::getcwd();

    for my $c ( 0 .. $#commands ) {

        #local()ize Perl’s global variables
        local ( $_, $!, $^E, $@, $? );

        #local()ize *Cpanel:: global variables
        Cpanel::initcp();

        #local()ize various things from the OS
        local %ENV = %ENV;
        local $0   = $0;
        my $umask = Umask::Local->new(umask);

        my $result = Cpanel::API::execute( @{ $commands[$c] } );
        push @batch_response, {
            (
                map { $_ => scalar $result->$_() }
                  qw(
                  data
                  metadata
                  status
                  errors
                  messages
                  warnings
                  )
            ),
        };

        if ( Cwd::getcwd() ne $cwd ) {

            #It might be ideal to chdir() to a filehandle opened
            #to /usr/local/cpanel, but the default perms for that
            #directory are 0711, which would make open() on that
            #directory fail when done as user, which would defeat
            #the whole point of this module.
            chdir($cwd) or die Cpanel::Exception::create( 'IO::ChdirError', { path => $cwd, error => $! } );
        }

        $error_handler_cr->( $c, $result ) if !$result->status();
    }

    return 1;
}

1;
