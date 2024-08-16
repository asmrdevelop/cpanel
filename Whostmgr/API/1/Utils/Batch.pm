package Whostmgr::API::1::Utils::Batch;

# cpanel - Whostmgr/API/1/Utils/Batch.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::Batch

=head1 SYNOPSIS

    my $args_hr = assemble_batch(
        [ listaccts => { arg1 => 'val1', arg2 => 123 } ],

        # NB: This will go through Cpanel::APICommon::Args::expand_array_refs()
        # as part of insertion into the batch:
        [ somethingelse => { list => [ 'foo', 'bar' ] } ],
    );

=head1 DESCRIPTION

This implements client logic for WHM API v1’s batch mode.

=cut

#----------------------------------------------------------------------

use Cpanel::Encoder::URI      ();
use Cpanel::HTTP::QueryString ();
use Cpanel::APICommon::Args   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $args_hr = assemble_batch( @CMDS_ARGS )

Returns a hash reference with the appropriate API arguments for the
C<batch> command.

@CMDS_ARGS is a list of 2-member array references; each array reference
is the function name and a hash reference of arguments to that function.

As a convenience, each hash reference will be copied and run through
C<Cpanel::APICommon::Args::expand_array_refs()> prior to insertion
into the batch.

=cut

sub assemble_batch (@cmds_args) {

    my @command_strs = map {
        my $cmd = Cpanel::Encoder::URI::uri_encode_str( $_->[0] );

        if ( $_->[1] ) {
            my %args = %{ $_->[1] };
            $cmd .= '?' . Cpanel::HTTP::QueryString::make_query_string( Cpanel::APICommon::Args::expand_array_refs( \%args ) );
        }

        $cmd;
    } @cmds_args;

    return Cpanel::APICommon::Args::expand_array_refs( { command => \@command_strs } );
}

#----------------------------------------------------------------------

=head2 $cmds_args_ar = parse_batch( \%BATCH )

Mostly an inverse operation to C<assemble_batch()>: takes a hash reference
of C<command> arguments as L<Cpanel::Form::Param> understands them and
converts them to an array of [ $command => \%args ]. A reference to that
array-of-arrayrefs is returned.

The reason why this isn’t fully an inverse operation of
C<assemble_batch()> is that C<assemble_batch()> calls
C<Cpanel::APICommon::Args::expand_array_refs()> on the passed-in arguments,
while this function does B<NOT> attempt to reverse that operation.

=cut

sub parse_batch ($args_hr) {

    require Cpanel::Form::Param;
    require Cpanel::HTTP::QueryString::Legacy;

    my $cpform = Cpanel::Form::Param->new( { 'parseform_hr' => $args_hr } );

    my @commands_and_args;

    #We have to authorize every command before we do any of them.
    for my $encoded_command ( $cpform->param('command') ) {
        my ( $command, $cmd_args ) = split( /\?/, $encoded_command, 2 );

        if ( defined $cmd_args ) {
            $cmd_args = Cpanel::HTTP::QueryString::Legacy::legacy_parse_query_string_sr( \$cmd_args );
        }

        push @commands_and_args, [ $command, $cmd_args ];
    }

    return \@commands_and_args;
}

1;
