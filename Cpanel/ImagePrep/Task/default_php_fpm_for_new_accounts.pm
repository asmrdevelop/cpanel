
# cpanel - Cpanel/ImagePrep/Task/default_php_fpm_for_new_accounts.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep::Task::default_php_fpm_for_new_accounts;

use cPstrict;

use parent 'Cpanel::ImagePrep::Task';

use Cpanel::PHPFPM::Config ();

=head1 NAME

Cpanel::ImagePrep::Task::default_php_fpm_for_new_accounts - An implementation subclass of Cpanel::ImagePrep::Task. See parent class for interface.

=cut

sub _description {
    return <<EOF;
Disable php-fpm for new accounts before snapshotting.  Enable php-fpm for new
accounts if appropriate for a newly launched instance.
EOF
}

sub _type { return 'non-repair only' }

sub _pre ($self) {
    Cpanel::PHPFPM::Config::set_default_accounts_to_fpm(0);
    return $self->PRE_POST_OK;
}

sub _post ($self) {
    Cpanel::PHPFPM::Config::set_default_accounts_to_fpm(1) if Cpanel::PHPFPM::Config::should_default();
    return $self->PRE_POST_OK;
}

1;
