
# cpanel - Cpanel/BoxTrapper/Actions.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::BoxTrapper::Actions;

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel::BoxTrapper::CORE ();
use Cpanel::Exception        ();
use Cpanel::Regex            ();
use Cpanel::SafeFile         ();

=head1 MODULE

C<Cpanel::BoxTrapper::Actions>

=head1 DESCRIPTION

C<Cpanel::BoxTrapper::Actions> provides action processing tools for queued messages.

=head1 GLOBALS

=head2 @ALL_ACTIONS - string[]

List of actions handled by this module.

=cut

our @ALL_ACTIONS = qw(deliver deliverall delete deleteall whitelist blacklist ignore);

=head1 CONSTRUCTORS

=head2 new(INIT, OPTS)

Creates a new C<Cpanel::BoxTrapper::Actions> object.

=head3 ARGUMENTS

=over

=item INIT - hashref

Initial data for the C<Cpanel::BoxTrapper::Actions> object.

=item OPTS - hashref

Output formatting options.

=back

=cut

sub new {
    my ( $class, $init, $opts ) = @_;
    $init = {} if !$init;

    my $self = {%$init};
    bless $self, $class;
    $self->init($opts);

    return $self;
}

=head1 METHODS

=head2 is_initialized()

Checks if the instance was correctly initialize.

=head3 RETURNS

Boolean - 1 if initialized, 0 if not.

=cut

sub is_initialized {
    my $self = shift;
    return $self->{initialized} ? 1 : 0;
}

=head2 is_operator_available(OPERATOR)

Checks if the operator is supported.

=head3 ARGUMENTS

=over

=item OPERATOR - string

Operator to check.

=back

=head3 RETURNS

Boolean - 1 if available, 0 if not.

=cut

sub is_operator_available {
    my ( $self, $operator ) = @_;
    return 0 if !$self->is_initialized();

    if ( grep { $_ eq $operator } qw(deliverall deleteall) ) {
        return -e $self->{verify_path} ? 1 : 0;
    }
    return 1 if grep { $_ eq $operator } qw(deliver delete whitelist blacklist ignore);
    return 0;
}

=head2 init(OPTS)

Initiliaze the C<Cpanel::BoxTrapper::Actions> object. Handles all the prechecks to make sure the system is setup right.

=head3 ARGUMENTS

=over

=item OPTS - hashref

Output formatting options.

=back

=cut

sub init {
    my ( $self, $opts ) = @_;

    $self->{opts} = $opts || { uapi => 1 };

    Cpanel::BoxTrapper::CORE::_handle_error(
        Cpanel::Exception::create( 'InvalidParameter', 'You must define “[_1]” in the [asis,init] parameter.', ['account'] ),
        $self->{opts},
    ) if !$self->{account};

    Cpanel::BoxTrapper::CORE::_handle_error(
        Cpanel::Exception::create( 'InvalidParameter', 'You must define “[_1]” in the [asis,init] parameter.', ['message_file'] ),
        $self->{opts},
    ) if !$self->{message_file};

    if ( !Cpanel::BoxTrapper::CORE::_role_is_enabled() ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext('Sorry, the role for this feature is not available.'),
            $opts
        );
        return;
    }

    if ( $Cpanel::CPDATA{'DEMO'} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext('Sorry, this feature is disabled in demo mode.'),
            $self->{opts},
        );
        return;
    }

    if ( $Cpanel::appname eq 'webmail' ) {
        $self->{account} = $Cpanel::authuser;
    }

    ( $self->{homedir} ) = Cpanel::BoxTrapper::CORE::BoxTrapper_getaccountinfo( $self->{account}, undef, $self->{opts} );
    if ( !$self->{homedir} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to locate the email account “[_1]”.', $self->{account} ),
            $self->{opts},
        );
    }

    ( $self->{emaildir}, $self->{emaildeliverdir} ) = Cpanel::BoxTrapper::CORE::BoxTrapper_getemaildirs(
        $self->{account},
        $self->{homedir},
        $Cpanel::BoxTrapper::CORE::PERFORM_EMAIL_DIR_CHECKS,
        $Cpanel::BoxTrapper::CORE::CREATE_EMAIL_DIRS,
        $self->{opts},
    );
    if ( !$self->{emaildir} ) {
        _handle_error(
            locale()->maketext( 'The system failed to locate the email account “[_1]”.', $self->{account} ),
            $opts
        );
        return;
    }

    my ( $headers, $body_fh, $email, $message_path ) = ( undef, undef, '', '' );
    if ( $self->{message_file} ) {
        $self->{message_file} =~ s/$Cpanel::Regex::regex{'doubledot'}//g;

        $message_path = $self->{emaildir} . '/boxtrapper/queue/' . $self->{message_file};
        if ( -e $message_path ) {
            ( $headers, $body_fh ) = Cpanel::BoxTrapper::CORE::BoxTrapper_extract_headers_return_bodyglobref($message_path);

            $email = Cpanel::BoxTrapper::CORE::BoxTrapper_extractaddress( Cpanel::BoxTrapper::CORE::BoxTrapper_getheader( 'from', $headers ) );
            $email =~ s/$Cpanel::Regex::regex{'doubledot'}//g;
            Cpanel::BoxTrapper::CORE::_handle_error(
                locale()->maketext( 'The system could not parse the requested message: [_1]', $self->{message_file} ),
                $opts,
            ) if !$email;
        }
        else {
            Cpanel::BoxTrapper::CORE::_handle_error(
                locale()->maketext( 'The system failed to locate the requested message: [_1]', $self->{message_file} ),
                $opts,
            );
            return;
        }
    }

    $self->{message_id} = $self->{message_file};
    $self->{message_id} =~ s/\.msg$// if ( $self->{message_id} );
    $self->{email}        = $email;
    $self->{message_path} = $message_path;
    $self->{verify_path}  = $self->{emaildir} . "/boxtrapper/verifications/$email";
    $self->{headers}      = $headers;
    $self->{body_fh}      = $body_fh;

    # All done
    $self->{initialized} = 1;
    return;
}

=head2 deliver_all()

Delivers all the message like the current message.

=cut

sub deliver_all {    ## no critic qw(Subroutines::ProhibitExcessComplexity) This code was refactored out of the API 1 equivalent, requires more refactoring to remove this complexity issue.
    my ($self) = @_;

    return if !$self->is_initialized();

    if ( !-e $self->{verify_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to locate the verification file “[_1]” for the email account “[_2]”.', $self->{verify_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    if ( !-r $self->{verify_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system could not access the verification file “[_1]” for the email account “[_2]”.', $self->{verify_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    my $verflock = Cpanel::SafeFile::safeopen( my $MSGIDS, '<', $self->{verify_path} );
    if ( !$verflock ) {
        my $error = $!;
        Cpanel::BoxTrapper::CORE::_handle_warn(
            locale()->maketext( "The system failed to read from “[_1]” with the error: [_2]", $self->{verify_path}, $error ),
            "The system failed to read from $self->{verify_path} with the error: $error",
            $self->{opts},
        );
        return;
    }

    my @failed_removal;
    my @failed_delivery;
    my @delivered_messages;

    while ( my $message_id = <$MSGIDS> ) {
        chomp $message_id;
        my $message_file = $message_id . '.msg';
        my $message_path = $self->{emaildir} . '/boxtrapper/queue/' . $message_file;

        next if !-e $message_path;

        my ( $headers, $bodyfh ) = Cpanel::BoxTrapper::CORE::BoxTrapper_extract_headers_return_bodyglobref($message_path);
        if ( !@{$headers} ) {
            close($bodyfh);
            Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Skipping deliverall of message $message_id as it is not in the queue (from a deliverall)" );
            next;
        }

        push @{$headers}, "X-BoxTrapper-Queue: released via web action: deliverall\n";

        if (
            Cpanel::BoxTrapper::CORE::BoxTrapper_delivermessage(
                $self->{account},  1,
                $self->{emaildir}, $self->{emaildeliverdir},
                $headers,          $bodyfh
            )
        ) {
            Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 3, $self->{emaildir}, "delivered message $message_path from queue via messageaction: deliverall" );
        }
        else {
            push @failed_delivery, $message_id;
            Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to deliver $message_path from queue: $!" );
            next;
        }

        if ( unlink $message_path ) {
            push @delivered_messages, $message_id;
        }
        else {
            push @failed_removal, $message_id;
            Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to remove delivered message ${message_id}.msg from queue: $!" );
            logger()->cplog( "Unable to unlink $message_path: $!", 'warn', __PACKAGE__, 1 );
        }
    }
    Cpanel::SafeFile::safeclose( $MSGIDS, $verflock );

    if (@delivered_messages) {
        Cpanel::BoxTrapper::CORE::BoxTrapper_removefromsearchdb( $self->{emaildir}, \@delivered_messages );
    }

    if (@failed_removal) {
        if ( my $verflock = Cpanel::SafeFile::safeopen( my $MSGIDS, '>', $self->{verify_path} ) ) {
            print $MSGIDS join( "\n", @failed_removal ) . "\n";
            Cpanel::SafeFile::safeclose( $MSGIDS, $verflock );
        }
        else {
            logger()->warn("Could not write to BoxTrapper verification file: $self->{verify_path}.");
            return {
                matches => \@delivered_messages,
                (
                    scalar @failed_removal > 0 || scalar @failed_delivery > 0
                    ? (
                        failures => {
                            ( scalar @failed_delivery > 0 ? ( delivery => \@failed_delivery ) : () ),
                            ( scalar @failed_removal > 0  ? ( removal  => \@failed_removal )  : () ),
                        }
                      )
                    : ()
                ),
                warning => 1,
                reason  => locale()->maketext( 'The system failed to update the verification file “[_1]”.', $self->{verify_path} ) || '',
            };
        }
    }
    else {
        if ( !unlink $self->{verify_path} ) {
            logger()->cplog( "Failed to unlink $self->{verify_path}: $!", 'warn', __PACKAGE__, 1 );
            return {
                matches => \@delivered_messages,
                (
                    scalar @failed_removal > 0 || scalar @failed_delivery > 0
                    ? (
                        failures => {
                            ( scalar @failed_delivery > 0 ? ( delivery => \@failed_delivery ) : () ),
                            ( scalar @failed_removal > 0  ? ( removal  => \@failed_removal )  : () ),
                        }
                      )
                    : ()
                ),
                warning => 1,
                reason  => locale()->maketext( 'The system failed to remove the verification file “[_1]”.', $self->{verify_path} ) || '',
            };
        }
    }

    my $some_failures = @failed_removal > 0 || @failed_delivery > 0 ? 1 : 0;
    my $reason;
    if ( @failed_removal && @failed_delivery ) {
        $reason = locale()->maketext('The system failed to deliver or cleanup some of the matching messages.');
    }
    elsif (@failed_delivery) {
        $reason = locale()->maketext('The system failed to deliver some of the matching messages.');
    }
    elsif (@failed_removal) {
        $reason = locale()->maketext('The system failed to cleanup some of the matching messages that were delivered.');
    }
    return {
        matches => \@delivered_messages,
        (
            scalar @failed_removal > 0 || scalar @failed_delivery > 0
            ? (
                failures => {
                    ( scalar @failed_delivery > 0 ? ( delivery => \@failed_delivery ) : () ),
                    ( scalar @failed_removal > 0  ? ( removal  => \@failed_removal )  : () ),
                }
              )
            : ()
        ),
        ( $some_failures ? ( warning => 1 )       : () ),
        ( $some_failures ? ( reason  => $reason ) : () ),
    };
}

=head2 deliver()

Delivers the current message.

=cut

sub deliver {
    my ($self) = @_;

    return if !$self->is_initialized();

    if ( !-e $self->{message_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to locate the message file “[_1]” for the email account “[_2]”.', $self->{message_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    if ( !-r $self->{message_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system could not read the message file “[_1]” for the email account “[_2]”.', $self->{message_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    push @{ $self->{headers} }, "X-BoxTrapper-Queue: released via web action: deliver\n";

    if (
        Cpanel::BoxTrapper::CORE::BoxTrapper_delivermessage(
            $self->{account},  1,
            $self->{emaildir}, $self->{emaildeliverdir},
            $self->{headers},  $self->{body_fh}
        )
    ) {
        $self->{body_fh} = undef;
        Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 3, $self->{emaildir}, "delivered message $self->{message_path} from queue via messageaction: deliver" );
    }
    else {
        Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to deliver $self->{message_path} from queue: $!" );
        logger()->warn("Unable to deliver messages due to I/O error");
        return {
            failed   => 1,
            failures => [ $self->{message_id} ],
            reason   => locale()->maketext('The system could not deliver the message.'),
        };
    }

    if ( unlink $self->{message_path} ) {
        Cpanel::BoxTrapper::CORE::BoxTrapper_removefromsearchdb( $self->{emaildir}, $self->{message_file}, $self->{opts} );
    }
    else {
        Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to remove delivered message $self->{message_path} from queue: $!" );
        logger()->cplog( "Unable to unlink $self->{message_path}: $!", 'warn', __PACKAGE__, 1 );
        return {
            matches => [ $self->{message_id} ],
            warning => 1,
            reason  => locale()->maketext( 'The system failed to remove the message file “[_1]” for the email account “[_2]”.', $self->{message_path}, $self->{account} ) || '',
        };
    }

    return {
        matches => [ $self->{message_id} ],
    };
}

=head2 delete()

Deletes the current message.

=cut

sub delete {
    my ($self) = @_;

    return if !$self->is_initialized();

    if ( !-e $self->{message_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to locate the message file “[_1]” for the email account “[_2]”.', $self->{message_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    if ( unlink $self->{message_path} ) {
        Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Deleted $self->{message_path} from $self->{email}" );
        Cpanel::BoxTrapper::CORE::BoxTrapper_removefromsearchdb( $self->{emaildir}, $self->{message_path} );
        return {
            matches => [ $self->{message_id} ],
        };
    }
    else {
        my $exception = $!;
        logger()->cplog( "Failed to unlink  $self->{message_path}: $exception", 'warn', __PACKAGE__, 1 );
        Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to delete $self->{message_path}: $exception" );
        return {
            failures => [ $self->{message_id} ],
            failed   => 1,
            reason   => locale()->maketext( 'The system could not delete the message file “[_1]” with the following error: [_2]', $self->{message_path}, $exception ),
        };
    }
}

=head2 delete_all()

Deletes all the message like the current message.

=cut

sub delete_all {
    my ($self) = @_;

    return if !$self->is_initialized();

    if ( !-e $self->{verify_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to locate the verification file “[_1]” for the email account “[_2]”.', $self->{verify_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    if ( !-r $self->{verify_path} ) {
        Cpanel::BoxTrapper::CORE::_handle_error(
            locale()->maketext( 'The system failed to access the verification file “[_1]” for the email account “[_2]”.', $self->{verify_path}, $self->{account} ),
            $self->{opts},
        );
        return;
    }

    my $verflock = Cpanel::SafeFile::safeopen( my $MSGIDS, '<', $self->{verify_path} );
    if ( !$verflock ) {
        my $error = $!;

        Cpanel::BoxTrapper::CORE::_handle_warn(
            locale()->maketext( "The system failed to read from “[_1]” with the error: [_2]", $self->{verify_path}, $error ),
            "The system failed to read from $self->{verify_path} with the error: $error",
            $self->{opts},
        );
        return;
    }

    my @deleted_messages;
    my @failed_deletion;
    while ( my $message_id = <$MSGIDS> ) {
        chomp $message_id;
        my $message_file = $message_id . '.msg';
        my $message_path = $self->{emaildir} . '/boxtrapper/queue/' . $message_file;
        if ( -e $message_path ) {
            if ( unlink $message_path ) {
                Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Deleted $message_file from $self->{email}" );
                push @deleted_messages, $message_id;
            }
            else {
                logger()->cplog( "Failed to unlink $message_path: $!", 'warn', __PACKAGE__, 1 );
                Cpanel::BoxTrapper::CORE::BoxTrapper_clog( 2, $self->{emaildir}, "Unable to delete $message_path: $!" );
                push @failed_deletion, $message_id;
            }
        }
    }
    Cpanel::SafeFile::safeclose( $MSGIDS, $verflock );

    Cpanel::BoxTrapper::CORE::BoxTrapper_removefromsearchdb( $self->{emaildir}, \@deleted_messages, $self->{opts} );

    if ( !unlink $self->{verify_path} ) {
        logger()->cplog( "Failed to unlink $self->{verify_path}: $!", 'warn', __PACKAGE__, 1 );
        return {
            matches => \@deleted_messages,
            ( scalar @failed_deletion > 0 ? ( failures => \@failed_deletion ) : () ),
            warning => 1,
            reason  => locale()->maketext( 'The system failed to remove verification file “[_1]”.', $self->{verify_path} ) || '',
        };
    }

    return {
        matches => \@deleted_messages,
        ( scalar @failed_deletion > 0 ? ( failures => \@failed_deletion ) : () ),
    };
}

=head2 whitelist()

Whitelist the from address from the message.

=cut

sub whitelist {
    my $self = shift;
    return if !$self->is_initialized();

    if ( !Cpanel::BoxTrapper::CORE::BoxTrapper_addaddytolist( 'white', $self->{email}, $self->{emaildir}, $self->{opts} ) ) {
        return {
            matches => [ $self->{message_id} ],
            failed  => 1,
            reason  => locale()->maketext( 'The system failed to add the “[_1]” to the blacklist.', $self->{email} ),
        };
    }

    return {
        matches => [ $self->{message_id} ],
    };
}

=head2 blacklist()

Blacklists the from address from the message.

=cut

sub blacklist {
    my $self = shift;
    return if !$self->is_initialized();

    if ( !Cpanel::BoxTrapper::CORE::BoxTrapper_addaddytolist( 'black', $self->{email}, $self->{emaildir}, $self->{opts} ) ) {
        return {
            matches => [ $self->{message_id} ],
            failed  => 1,
            reason  => locale()->maketext( 'The system failed to add the “[_1]” to the blacklist.', $self->{email} ),
        };
    }

    return {
        matches => [ $self->{message_id} ],
    };
}

=head2 ignore()

Ignores the from address from the message.

=cut

sub ignore {
    my $self = shift;
    return if !$self->is_initialized();

    if ( !Cpanel::BoxTrapper::CORE::BoxTrapper_addaddytolist( 'ignore', $self->{email}, $self->{emaildir}, $self->{opts} ) ) {
        return {
            matches => [ $self->{message_id} ],
            failed  => 1,
            reason  => locale()->maketext( 'The system failed to add the “[_1]” to the ignore list.', $self->{email} ),
        };
    }

    return {
        matches => [ $self->{message_id} ],
    };
}

1;
