package Whostmgr::Transfers::Session::Items::MailboxConversion;

# cpanel - Whostmgr/Transfers/Session/Items/MailboxConversion.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw(Whostmgr::Transfers::Session::Item Whostmgr::Transfers::Session::Items::Schema::MailboxConversion);

our $VERSION = '1.0';

use Cpanel::Email::Convert::User ();
use Cpanel::Exception            ();

sub module_info {
    my ($self) = @_;

    return { 'item_name' => 'Account' };
}

sub restore {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(
              _restore_init
              _convert_cpuser
            ),

            ( $self->can('post_restore') ? 'post_restore' : () )
        ]
    );
}

sub _restore_init {
    my ($self) = @_;

    $self->session_obj_init();

    $self->{'cp_user'}       = $self->{'input'}->{'user'} || $self->item();    # self->item() FKA $self->{'input'}->{'user'};
    $self->{'skip_removal'}  = $self->{'input'}->{'skip_removal'};
    $self->{'target_format'} = $self->{'input'}->{'target_format'};
    $self->{'source_format'} = $self->{'input'}->{'source_format'};
    return $self->validate_input( [qw(session_obj session_info output_obj skip_removal)] );
}

sub is_transfer_item {
    return 0;
}

#tested directly
sub _convert_cpuser {
    my ($self) = @_;

    my $time          = time();
    my $skip_removal  = $self->{'skip_removal'};
    my $cp_user       = $self->{'cp_user'};
    my $target_format = $self->{'target_format'};
    my $source_format = $self->{'source_format'};

    my $failures_ar = Cpanel::Email::Convert::User->new(
        'system_user'   => $cp_user,
        'skip_removal'  => $skip_removal,
        'target_format' => $target_format,
        'source_format' => $source_format
    )->convert_all();

    if (@$failures_ar) {

        #cf. Whostmgr::Transfers::Session::Items::AccountRemoteRoot
        my @warnings = map { { msg => [ $self->_locale()->maketext( 'The system failed to convert “[_1]” to “[_2]” because of an error: [_3]', $_->[0], $target_format, Cpanel::Exception::get_string( $_->[1] ) ) ] } } @$failures_ar;

        $self->set_warnings( \@warnings );
    }

    return 1;
}

1;
