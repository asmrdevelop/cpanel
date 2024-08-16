package Whostmgr::API::1::Contact;

# cpanel - Whostmgr/API/1/Contact.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                         ();
use Cpanel::iContact::EventImportance         ();
use Cpanel::iContact::EventImportance::Writer ();
use Whostmgr::API::1::Utils                   ();

use constant NEEDS_ROLE => {
    get_all_contact_importances              => undef,
    get_application_contact_event_importance => undef,
    get_application_contact_importance       => undef,
    set_application_contact_event_importance => undef,
    set_application_contact_importance       => undef,
};

# Note: we accept any event or app as long as its alphanumeric
# because we want to be able to set the value for an application
# that is not installed yet if we know that we do not want to get
# notifications for it upon upgrade.

sub get_all_contact_importances {
    my ( $args, $metadata ) = @_;
    my $data = Cpanel::iContact::EventImportance->new()->get_all_contact_importance();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'importances' => $data };
}

sub get_application_contact_event_importance {
    my ( $args, $metadata ) = @_;
    my $app = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'app' );
    _validate_alphanumeric( 'app', $app );
    my $event = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'event' );
    _validate_alphanumeric( 'event', $event );

    my $importance     = Cpanel::iContact::EventImportance->new()->get_event_importance( $app, $event );
    my %number_to_name = reverse %Cpanel::iContact::EventImportance::NAME_TO_NUMBER;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'importance' => $importance, 'name' => $number_to_name{$importance} };
}

sub get_application_contact_importance {
    my ( $args, $metadata ) = @_;
    my $app = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'app' );
    _validate_alphanumeric( 'app', $app );

    my $importance     = Cpanel::iContact::EventImportance->new()->get_event_importance($app);
    my %number_to_name = reverse %Cpanel::iContact::EventImportance::NAME_TO_NUMBER;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'importance' => $importance, 'name' => $number_to_name{$importance} };
}

sub set_application_contact_event_importance {
    my ( $args, $metadata ) = @_;
    my $app = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'app' );
    _validate_alphanumeric( 'app', $app );
    my $event = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'event' );
    _validate_alphanumeric( 'event', $event );
    my $importance        = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'importance' );
    my $importance_number = _get_event_importance_number_or_die($importance);

    my $imp_writer = Cpanel::iContact::EventImportance::Writer->new();
    $imp_writer->set_event_importance( $app, $event, $importance_number );
    $imp_writer->save_and_close();    # this already does _or_die

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub set_application_contact_importance {
    my ( $args, $metadata ) = @_;
    my $app = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'app' );
    _validate_alphanumeric( 'app', $app );
    my $importance        = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'importance' );
    my $importance_number = _get_event_importance_number_or_die($importance);

    my $imp_writer = Cpanel::iContact::EventImportance::Writer->new();
    $imp_writer->set_application_importance( $app, $importance_number );
    $imp_writer->save_and_close();    # this already does _or_die

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub _validate_alphanumeric {
    my ( $name, $value ) = @_;
    if ( $value !~ m{^[0-9A-Za-z]+$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter value of “[_2]” is invalid. It must only contain alphanumeric characters.', [ $name, $value ] );
    }
    return 1;

}

sub _get_event_importance_number_or_die {
    my ($importance) = @_;

    return $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{$importance} if exists $Cpanel::iContact::EventImportance::NAME_TO_NUMBER{$importance};

    return $importance if ( grep { $_ eq $importance } values %Cpanel::iContact::EventImportance::NAME_TO_NUMBER );

    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter “[_2]” is invalid and may only be one of “[list_or,_3]”.',
        [
            'importance', $importance,
            [ sort keys %Cpanel::iContact::EventImportance::NAME_TO_NUMBER, sort values %Cpanel::iContact::EventImportance::NAME_TO_NUMBER ]
        ]
    );

}

1;
