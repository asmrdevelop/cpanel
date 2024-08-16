
# cpanel - Whostmgr/Store/Template.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Store::Template;

use strict;
use warnings;
use Carp ();

use Cpanel::Template ();

=head1 NAME

Whostmgr::Store::Template

=head1 DESCRIPTION

Interface for processing reusable install status templates to be used in WHM with
the Whostmgr::Store purchase/install process.

This module produces HTML output to stdout for the purpose of displaying in a browser.

=head1 SYNOPSIS

  # All of the implementation-specific template data like product name
  # and custom status messages are pulled in from the implementation instance.

  my $handler = Whostmgr::Store::Product::MyModule->new();

  my $store_template = Whostmgr::Store::Template->new(
    implementation_instance => $handler,
  );

  # The do_install method both displays the status templates and performs the installation itself.
  # If you need more fine-grained control over what happens on success/failure/etc., then you can
  # use the rest of the object interface instead of do_install.
  $store_template->do_install;

=head1 CONSTRUCTION

=head2 new( implementation_instance => ... )

=head3 Arguments

Key/value pairs:

=over

=item * implementation_instance - String - (Required) An instance of your implementation class,
which must be a subclass of Whostmgr::Store. One existing example of such an implementation is
Whostmgr::Imunify360.

=item * success_addendum - String - (Optional) The path to a template relative to ULC/whostmgr/docroot
which contains additional output to display in the success box upon success. The rules for this template
are:

=over

=item * It must contain a div with id="addendum"

=item * It must have a script block with a call to showSuccessAddendum()

=back


=item * failure_addendum - String (Optional) Same as C<success_addendum>, but for the failure case.

=over

=item * It must contain a div with id="addendum"

=item * It must have a script block with a call to showFailureAddendum()

=back

=item * skip_redirect - Boolean (Optional) If provided and true, do not automatically redirect on success.
The "Go Back" link will still be shown with the same redirect target.

=back

=cut

sub new {
    my ( $package, %attrs ) = @_;

    my $implementation_instance = delete( $attrs{implementation_instance} ) || Carp::croak('You must provide the implementation_instance attribute.');
    my $success_addendum        = delete $attrs{success_addendum}           || '';
    my $failure_addendum        = delete $attrs{failure_addendum}           || '';
    my $skip_redirect           = delete $attrs{skip_redirect}              || 0;
    Carp::croak( 'Unexpected attribute(s) provided: ' . join( ', ', sort keys %attrs ) ) if %attrs;

    return bless {
        implementation_instance => $implementation_instance,
        success_addendum        => $success_addendum,
        failure_addendum        => $failure_addendum,
        skip_redirect           => $skip_redirect,
    }, $package;
}

=head1 MAIN INTERFACE

=head2 do_install()

Perform the installation and display/update the status templates as appropriate based on
the success or failure of the operation. Normally, this should be the only method that
you need to call other than the constructor.

=cut

sub do_install {
    my ($self) = @_;

    $self->show_installing;

    local $@;
    my ( $is_installed, $install_detail ) = eval { $self->handler->ensure_installed(); };
    my $exception = $@;

    if ($is_installed) {
        $self->show_success(
            install_detail => $install_detail,
        );
    }
    else {
        $self->show_failure(
            exception => $exception,
        );
    }

    return;
}

=head1 OTHER METHODS (should not normally be called directly)

=head2 show_installing()

Show the "installing" template. This is a required step before showing any other templates.

=cut

sub show_installing {
    my ( $self, %garbage ) = @_;
    Carp::croak( 'Unexpected attribute(s) provided: ' . join( ', ', sort keys %garbage ) ) if %garbage;

    $self->{show_installing_called}++;

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'store/product_installing.tmpl',
            data            => {
                redirect                 => $self->handler->default_redirect_url,       # can vary from instance to instance
                skip_redirect            => $self->{skip_redirect},
                product_name             => $self->handler->HUMAN_PRODUCT_NAME,
                log_path                 => $self->handler->LOG_PATH,
                install_duration_warning => $self->handler->INSTALL_DURATION_WARNING,
                background_install       => $self->handler->BACKGROUND_INSTALL
            }
        }
    );

    $self->handler->logger->info("The @{[$self->{implementation_instance}->HUMAN_PRODUCT_NAME]} installation has started …");

    return;
}

=head2 show_success( install_detail => ... )

Show the success template.

=head3 Arguments

=over

=item * success_detail - String - (Optional) If the installer ran into a "partial success" condition,
the information about what failed may be added here and will be displayed in the browser.

=back

=cut

sub show_success {
    my ( $self, %attrs ) = @_;

    my $install_detail = delete $attrs{install_detail};
    Carp::croak( 'Unexpected attribute(s) provided: ' . join( ', ', sort keys %attrs ) ) if %attrs;

    # This template must be displayed to the same page that already has the "installing" template displayed
    # because the "success" template is nothing but a modification on top of the existing template.
    if ( !$self->{show_installing_called} ) {
        Carp::croak('show_installing needs to have already been called in the same page load as show_success');
    }

    $self->handler->logger->info("The @{[$self->{implementation_instance}->HUMAN_PRODUCT_NAME]} installation completed successfully.");

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'store/product_installed.tmpl',
            data            => { $install_detail ? ( install_detail => $install_detail ) : () }
        }
    );

    if ( $self->{success_addendum} ) {
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => $self->{success_addendum},
            }
        );
    }

    return;
}

=head2 show_failure( install_detail => ... )

Show the failure template.

=head3 Arguments

=over

=item * exception - String - (Optional but recommended) If the failure that occurred resulted in an exception or
other error message, it should be included here.

=back

=cut

sub show_failure {
    my ( $self, %attrs ) = @_;

    my $exception = delete $attrs{exception};    # technically optional but ought to be provided if possible

    # This template must be displayed to the same page that already has the "installing" template displayed
    # because the "failure" template is nothing but a modification on top of the existing template.
    if ( !$self->{show_installing_called} ) {
        Carp::croak('show_installing needs to have already been called in the same page load as show_failure');
    }

    $self->handler->logger->info("The @{[$self->{implementation_instance}->HUMAN_PRODUCT_NAME]} installation failed with error: $exception");

    Cpanel::Template::process_template(
        'whostmgr',
        {
            'template_file' => 'store/product_purchased_not_installed.tmpl',
            data            => {
                exception => $exception,
            }
        }
    );

    if ( $self->{failue_addendum} ) {
        Cpanel::Template::process_template(
            'whostmgr',
            {
                'template_file' => $self->{failue_addendum},
            }
        );
    }

    return;
}

=head2 handler()

Returns the purchase/install handler object, which is an instance of a subclass of Whostmgr::Store.

=cut

sub handler {
    my ($self) = @_;
    return $self->{implementation_instance};
}

1;
