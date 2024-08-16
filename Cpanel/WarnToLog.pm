package Cpanel::WarnToLog;

# cpanel - Cpanel/WarnToLog.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WarnToLog

=head1 SYNOPSIS

    # Whatever warn() handler is active here …

    {
        my $warn_catcher = Cpanel::WarnToLog->new();

        # Here we write to the cPanel & WHM log.
    }

    # Back to the previous warn() handler.

=head1 DESCRIPTION

This provides a simple way to ensure that C<warn()>s are sent to the
cPanel & WHM log.

This avoids the need to replace C<warn()> calls with, e.g.,
C<Cpanel::Debug::log_warn()>. We thus avoid tight-coupling such
code to this specific method of logging; a given piece of code could
log to, e.g., a screen, a different log file, etc. depending on context.

=cut

#----------------------------------------------------------------------

use Cpanel::Debug;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class. While $obj lives, C<warn()>s will go to the
main cPanel & WHM log (unless something else writes to C<$SIG{'__WARN__'}>.

=cut

sub new ($class) {
    my $obj = [ $SIG{'__WARN__'} ];

    $SIG{'__WARN__'} = *_log_warn;    ## no critic (RequireLocalizedPunctuationVars)

    return bless $obj, $class;
}

sub DESTROY ($self) {
    $SIG{'__WARN__'} = $self->[0];    ## no critic (RequireLocalizedPunctuationVars)

    return;
}

# overwritten in tests
*_log_warn = *Cpanel::Debug::log_warn;

1;
