package Cpanel::Parser::Rsync;

# cpanel - Cpanel/Parser/Rsync.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Parser::Rsync

=head1 DESCRIPTION

A parser for output from L<rsync(1)>. Extends L<Cpanel::Parser::Base>.

This C<output()>s progress updates and completion notices.

This documentation postdates the implementation and does not describe
it fully; please see the code for details.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Parser::Base';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    my $self = $class->SUPER::new();

    @{$self}{ 'percent', 'count' } = ( 0, undef );

    return $self;
}

=head2 $printed = I<OBJ>->process_line( $STR )

Callback for the rsync process’s STDOUT.

=cut

sub process_line {
    my ( $self, $line ) = @_;

    # CentOS 6’s rsync says “to-check”, but CentOS 7’s says “to-chk”.
    # So we just have to look for both.
    if ( $line =~ /\s+to-(?:chk|check)=([0-9]+)\/([0-9]+)/ ) {
        my $file_count = $1;

        $self->{'count'} = $file_count if !defined $self->{'count'};

        my $new_percent = $self->{'count'} ? ( int( ( ( $self->{'count'} - $file_count ) / $self->{'count'} ) * 100 ) ) : 1;
        if ( $new_percent > $self->{'percent'} ) {
            $self->{'percent'} = $new_percent;
            $self->output("…$self->{'percent'} % …\n");
        }
    }
    elsif ( $line =~ m{^(?:total|sent|receiving)} ) {
        $self->output($line);
        $self->{'success'} = 1 if $line =~ m{^total size};
    }

    return 1;
}

=head2 $success_yn = I<OBJ>->finish()

See description in the base class’s documentation.

=cut

sub finish {
    my ($self) = @_;

    $self->process_line( $self->{'_buffer'} ) if length $self->{'_buffer'};

    if ( $self->{'percent'} < 100 ) {
        $self->{'percent'} = 100;
        $self->output("…$self->{'percent'} % …\n");
    }

    $self->clear_buffer();
    $self->clear_error_buffer();

    return $self->{'success'};
}

1;
