
# cpanel - Cpanel/ImagePrep/Output.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Output;

use cPstrict;
use Text::SimpleTable ();

=head1 NAME

Cpanel::ImagePrep::Output

=head1 STATIC METHODS

=head2 get_status_output_callback()

For use with snapshot_prep, post_snapshot, and regenerate_tokens:
Returns an object with a C<draw> (see below) method and a code ref
that accepts three string arguments corresponding to the Stage, Task,
and Status columns. The object may be used for producing the output
after rows have been collected.

=cut

sub get_status_output_callback {
    my ($package) = @_;
    my $self = {};
    $self->{table} = Text::SimpleTable->new( 9, 35, 30 );
    $self->{table}->row( 'Stage', 'Task', 'Status' );
    $self->{table}->hr;
    return bless( $self, $package ), sub { return $self->{table}->row(@_) };
}

=head2 get_list_output_callback()

For use with list_tasks:
Returns an object with a C<draw> method (see below) and a code ref
that accepts two string arguments corresponding to the Task and
Type columns. The Text::SimpleTable object may be used for producing
the output after rows have been collected.

=cut

sub get_list_output_callback {
    my ($package)   = @_;
    my $self        = {};
    my @field_names = ( 'Task', 'Type', 'Description' );
    $self->{check_output} = "## Checks: ##\n\n";
    $self->{task_output}  = "## Tasks: ##\n\n";
    return bless( $self, $package ), sub {
        my ($task_obj) = @_;
        my ( $task, $type, $description ) = map { $task_obj->$_ } 'task_name', 'type', 'description';
        $description =~ s/^(.*\S)/    $1/gm;
        $description =~ s/\s+\z//;
        my $is_check = $task_obj->isa('Cpanel::ImagePrep::Check');
        my $section  = $is_check ? 'check_output' : 'task_output';
        $self->{$section} .= sprintf( "%s - %s\n%s\n\n", $task, $type, $description );
    };
}

=head2 draw()

Return the assembled output, whether that is a status table or a task list.

=cut

sub draw {
    my ($self) = @_;
    return $self->{table}->draw if $self->{table};
    return "\n" . $self->{check_output} . "\n" . $self->{task_output};
}

1;
