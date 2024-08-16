package Cpanel::TaskRunner;

# cpanel - Cpanel/TaskRunner.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TaskRunner

=head1 DESCRIPTION

This module implements task-runner logic that will run a setup
of steps using C<Cpanel::CommandQueue> and output details about
the result of each step to a C<Cpanel::Output> object.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::CommandQueue      ();
use Cpanel::TaskRunner::Icons ();
use Cpanel::Set               ();

use constant _KNOWN_TAGS => ('final');

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 run( $OUTPUTTER, \@STEPS, \%INPUT, \%STATE )

Runs a set of @STEPS.

$OUTPUTTER is a L<Cpanel::Output> instance.

Each member of @STEPS is a hash reference that represents a single task:

=over

=item * C<code> (coderef) - the work to do

=item * C<label> (string) - a description of that work

=item * C<undo> (coderef) - (optional) the work to do, if any, that undoes what
C<code> did

=item * C<undo_label> (string or coderef) - (optional) a description of what
C<undo> does, or a coderef that returns such a description

=item * C<tags> (string[], optional) - any/all of:

=over

=item * C<final> - Indicates the last task that’s required for the conversion
to be considered “successful”. B<MUST> be assigned to no more than 1 task.
(If no task has this tag, then the last-given one has it by default.)

Any tasks that appear after this one in @STEPS are considered nonessential.
Failures reported from such steps will be reported as warnings and will
B<NOT> trigger rollback of earlier tasks.

=back

=back

Each C<code> is executed in sequence. If any (non-C<final>-tagged) C<code>
throws an exception, then all previous C<undo>s run, in reverse sequence.

%INPUT is the parameters given to the conversion logic. %STATE
allows for storage of run-time details. References to both of these
are given to the C<code> and C<undo> coderefs.

=cut

sub _FAILURE_MESSAGE {
    return locale()->maketext('The process failed.');
}

sub _validate_tags ($tags_ar) {
    my @bad = Cpanel::Set::difference(
        $tags_ar,
        [_KNOWN_TAGS],
    );

    _confess("Bad tag(s): @bad") if @bad;

    return;
}

sub _confess ($str) {
    require Carp;
    Carp::confess($str);
}

sub run ( $self, $output_obj, $steps_ar, $input_hr, $state_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    $output_obj = Cpanel::TaskRunner::_OUTPUT->new($output_obj);

    my $cq = Cpanel::CommandQueue->new();

    my $undo_indent;

    my $step_idx       = 0;
    my $first_undo_idx = 0;

    my $final_tag_seen;

    for my $step_hr (@$steps_ar) {
        my $this_step_idx = $step_idx;

        my @tags = $step_hr->{'tags'} ? @{ $step_hr->{'tags'} } : ();

        _validate_tags( \@tags );

        my $tolerate_failure_yn = $final_tag_seen;

        my @add_args = (
            sub {
                $output_obj->info("$Cpanel::TaskRunner::Icons::ICON{'start_step'} $step_hr->{'label'}");

                my $step_indent = $output_obj->create_log_level_indent();

                local $@;
                my $ok = eval {
                    $step_hr->{'code'}->( $input_hr, $state_hr );
                    1;
                };

                if ( !$ok ) {
                    my $err = $@;

                    if ($tolerate_failure_yn) {

                        # A warn handler below intercepts this.
                        warn $err;
                    }
                    else {
                        $output_obj->error($err);

                        my $summary = _FAILURE_MESSAGE();
                        if ( $this_step_idx > $first_undo_idx ) {
                            $summary .= locale()->maketext('The system will undo previous changes.');
                        }

                        # We’re going to roll back and so are no longer
                        # within the step; thus it’s sensible to undo
                        # the indent from the step.
                        undef $step_indent;

                        $output_obj->error("$Cpanel::TaskRunner::Icons::ICON{'error'} $summary");

                        $undo_indent = $output_obj->create_log_level_indent();

                        die $err;
                    }
                }
            },
        );

        $final_tag_seen ||= grep { $_ eq 'final' } @tags;

        if ( my $undo_cr = $step_hr->{'undo'} ) {

            # sanity check
            _confess('Undo with or after final task is useless!') if $final_tag_seen;

            $first_undo_idx ||= $this_step_idx;

            push @add_args, sub {
                my $label;

                if ( 'CODE' eq ref $step_hr->{'undo_label'} ) {
                    $label = $step_hr->{'undo_label'}->();
                }
                else {
                    $label = $step_hr->{'undo_label'};
                }

                $output_obj->info("$Cpanel::TaskRunner::Icons::ICON{'start_step'} $label") if length $label;

                my $indent = $output_obj->create_log_level_indent();

                $step_hr->{'undo'}->( $input_hr, $state_hr );
            };
        }

        $cq->add(@add_args);
    }

    local $SIG{'__WARN__'} = sub ($msg) {
        $output_obj->warn("$Cpanel::TaskRunner::Icons::ICON{'warning'} $msg");
    };

    $cq->run();

    return;
}

#----------------------------------------------------------------------

package Cpanel::TaskRunner::_OUTPUT;

use parent 'Cpanel::Output::Container::MethodProvider';

sub new ( $class, $output_obj ) {
    return bless { _logger => $output_obj }, $class;
}

1;
