# cpanel - Cpanel/Deprecation.pm                   Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Deprecation;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);

use cpcore;
our $VERSION = '1.0.0';
our $DEBUG   = 0;

=head1 MODULE

C<Cpanel::Deprecation>

=head1 DESCRIPTION

C<Cpanel::Deprecation> provides tools for logging the use of with deprecated features.

=head1 SYNOPSIS

  use Cpanel::Deprecation ();

  # Use these when there is no replacement
  warn_deprecated("old");
  warn_deprecated("old", '%s() function is deprecated and will be removed in a future release.');

  # Use these when there is a replacement we can recommend
  warn_deprecated_with_replacement("old_feature", "new_feature");
  warn_deprecated_with_replacement("old", "new", '%s() function is deprecated and will be removed in a future release, use the %s() function in all new code.');

=head1 FUNCTIONS

=head2 warn_deprecated_with_replacement($OLD, $NEW, $TEMPLATE)

Generate a deprecation message if this called on a sandbox. Use this method is there is a replacement for
the deprecated system.

=head3 ARGUMENTS

=over

=item $OLD - string

The name of the deprecated item.

=item $NEW - string

The name of the replacement for the deprecated item.

=back

=cut

sub warn_deprecated_with_replacement {
    my ( $old_name, $new_name, $template ) = @_;
    if ( is_sandbox() ) {
        $template //= '%s is deprecated and will be removed in a future release, use %s in all new code.';

        my $message = sprintf( "DEPRECATED: $template", $old_name, $new_name );
        if ($DEBUG) {
            require Cpanel::Carp;
            $message .= "\n" . Cpanel::Carp::safe_longmess();
        }
        _log($message);
        warn $message;
    }
    return 1;
}

=head2 warn_deprecated($OLD, $TEMPLATE)

Generate a deprecation message if this called on a sandbox. Use this method is there is not a replacement for
the deprecated system.

=head3 ARGUMENTS

=over

=item $OLD - string

The name of the deprecated item.

=back

=cut

sub warn_deprecated {
    my ( $old_name, $template ) = @_;
    if ( is_sandbox() ) {
        $template //= '%s is deprecated and will be removed in a future release.';
        my $message = sprintf( "DEPRECATED: $template", $old_name );
        _log($message);
        warn $message;
    }
    return 1;
}

=head2 is_sandbox()

Detect if this is running on a sandbox.

=head3 RETURNS

True when the system is a developer sandbox. False otherwise.

=cut

sub is_sandbox {
    return -e '/var/cpanel/dev_sandbox' ? 1 : 0;
}

=head2 _log($message)

Output the message to the deprecation log.

=cut

sub _log {
    require Cpanel::Debug;

    # Dont use Cpanel::Debug::log_deprecated since it dies in production
    # mode. Thats not what we want for soft deprecation but still present.
    return Cpanel::Debug::log_warn( $_[0] );
}

1;
