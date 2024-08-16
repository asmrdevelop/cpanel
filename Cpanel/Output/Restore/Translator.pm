package Cpanel::Output::Restore::Translator;

# cpanel - Cpanel/Output/Restore/Translator.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Output::Restore::Translator

=head1 SYNOPSIS

    my $term_out = Cpanel::Output::Formatted::Terminal->new();

    my $restore_out = Cpanel::Output::Restore::Translator::create($term_out);

    my ( $status, $msg ) = Whostmgr::Backup::Restore::load_transfers_then_restorecpmove(
        output_obj => $restore_out,

        # ...
    );

    die $msg if !$status;

=head1 DESCRIPTION

This module creates a L<Cpanel::Output> instance that “translates”
messages meant for L<Cpanel::Output::Restore> to messages that a
“normal”, text-based L<Cpanel::Output> instance can handle.
Restore-specific message types (e.g., C<control>) are converted to
plain C<out>, indentation is applied, etc.

=cut

#----------------------------------------------------------------------

use Cpanel::Output::Callback ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = create( $OUTPUT_OBJ )

Creates the needed object (see above discussion).

$OUTPUT_OBJ is a L<Cpanel::Output> instance that will receive
the “translated” messages.

=cut

sub create ($plain_output_obj) {
    my @indents;

    return Cpanel::Output::Callback->new(
        on_render => sub ($msg_hr) {

            # NB: $msg_hr->{'indent'} is not reliable;
            # we need instead to mimic the indentation logic
            # in Cpanel::Output::Restore. (Alas.)

            my $msgtype = $msg_hr->{'type'};

            if ( $msgtype eq 'start' ) {
                $plain_output_obj->out( $msg_hr->{'contents'}{'msg'} );
            }
            elsif ( $msgtype eq 'modulestatus' ) {

                # Some modules trigger a “modulestatus” message with
                # no message content.
                if ( my $msg = $msg_hr->{'contents'}{'statusmsg'} ) {

                    # “modulestatus” messages are evaluations of the
                    # previous module; hence, it makes sense for them
                    # to be indented.
                    my $indent = $plain_output_obj->create_indent_guard();

                    $plain_output_obj->out($msg);
                }
            }
            elsif ( $msgtype eq 'control' ) {
                my $action = $msg_hr->{'contents'}{'action'};

                # Don’t bother outputting these.
                return if $action eq 'percentage';

                if ( 0 == rindex( $action, 'start_', 0 ) ) {
                    $plain_output_obj->out( $msg_hr->{'contents'}{'msg'} );

                    push @indents, $plain_output_obj->create_indent_guard();
                }
                elsif ( 0 == rindex( $action, 'end_', 0 ) ) {

                    # For now ignore end notifications except
                    # to decrease the indentation level.

                    pop @indents;
                }
                else {
                    require Cpanel::JSON;

                    $plain_output_obj->warn(
                        "UNHANDLED ACTION ($action): " . Cpanel::JSON::Dump($msg_hr),
                    );
                }
            }
            else {
                $plain_output_obj->message( @{$msg_hr}{ 'type', 'contents', 'source' } );
            }
        },
    );
}

1;
