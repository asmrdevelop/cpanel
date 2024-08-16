
# cpanel - Cpanel/Email/Convert/CLI.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Email::Convert::CLI;

use strict;
use warnings;

use Cpanel::Email::Convert::User ();
use Cpanel::AcctUtils::Lookup    ();
use Cpanel::Exception            ();
use Cpanel::Locale               ();
use Pod::Usage;
use Getopt::Long ();

sub script {
    my ( $class, @input ) = @_;

    my %opts = (
        user                => '',
        email               => '',
        'delete-old-format' => 0,
    );

    Getopt::Long::GetOptionsFromArray(
        \@input,
        \%opts,
        'help',
        'user=s',
        'email=s',
        'delete-old-format'
      )
      or do {
        Pod::Usage::pod2usage(
            -exitval   => 'NOEXIT',
            -verbose   => 2,
            -noperldoc => 1,
        );
        return 1;
      };

    if ( $opts{'help'} ) {
        Pod::Usage::pod2usage(
            -exitval   => 'NOEXIT',
            -verbose   => 2,
            -noperldoc => 1,
        );
        return 0;
    }

    my $system_user;

    if ( length $opts{'email'} ) {

        if ( length $opts{'user'} ) {

            #“parameters” is not getting numerate() here because
            #a translator can see that “both” refers to the number 2.
            Pod::Usage::pod2usage(
                -exitval   => 'NOEXIT',
                -msg       => Cpanel::Exception::create( 'InvalidParameter', 'You may not submit both [list_and_quoted,_1] parameters.', [ [ 'user', 'email' ] ] )->to_string_no_id(),
                -verbose   => 2,
                -noperldoc => 1,
            );
            return 1;
        }

        $system_user = Cpanel::AcctUtils::Lookup::get_system_user( $opts{'email'} );
    }
    elsif ( length $opts{'user'} ) {
        $system_user = $opts{'user'};
    }
    else {
        Pod::Usage::pod2usage(
            -exitval   => 'NOEXIT',
            -msg       => Cpanel::Exception::create( 'MissingParameter', 'The argument [list_or_quoted,_1] is required.', [ [ 'user', 'email' ] ] )->to_string_no_id(),
            -verbose   => 2,
            -noperldoc => 1,
        );
        return 1;
    }

    my $skip_removal = ( $opts{'delete-old-format'} ? 0 : 1 );

    my $convert_obj = Cpanel::Email::Convert::User->new(
        'system_user'   => $system_user,
        'skip_removal'  => $skip_removal,
        'target_format' => $class->_TARGET_FORMAT(),
        'source_format' => $class->_SOURCE_FORMAT(),
    );

    if ( length $opts{'email'} ) {
        $convert_obj->convert_email_account( $opts{'email'} );
    }
    else {
        my $locale;
        for my $failure_ar ( @{ $convert_obj->convert_all() } ) {
            $locale ||= Cpanel::Locale->get_handle();

            print STDERR "\n\n" . ( '-' x 50 ) . "\n";
            print STDERR $locale->maketext( 'The system failed to convert “[_1]” to “[_2]” because of an error: [_3]', $failure_ar->[0], $class->_TARGET_FORMAT(), Cpanel::Exception::get_string( $failure_ar->[1] ) );
        }
    }

    return 0;
}

1;
