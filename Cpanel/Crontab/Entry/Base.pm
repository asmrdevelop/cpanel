# cpanel - Cpanel/Crontab/Entry/Base.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Crontab::Entry::Base;

=encoding utf-8

=head1 NAME

Cpanel::Crontab::Entry::Base - Base class for logic to manage system-level cron jobs

=head1 SYNOPSIS

    # This examples presume that Cpanel::Crontab::Entry::Base::Impl is a concrete
    # implementation of this base class.

    my $ct_event = Cpanel::Crontab::Entry::Base::Impl->get_entry();

    Cpanel::Crontab::Entry::Base::Impl->ensure_that_entry_exists();

    Cpanel::Crontab::Entry::Base::Base::Impl->delete_entry();

=head1 DESCRIPTION

This module implements a base abstraction for managing crontab entries where
a system-level crontab file contains a single entry for a given command.

Concrete implentations need only override the C<_COMMAND> and C<_CRON_FILE>
functions to specify what command to execute and which file to store the
crontab entry in. Note that the default implementation of these functions throw
AbstractClass exceptions if the implementing module does not override them.

Additionally, C<_get_crontab_hour_minute_opts> can be overridden to define the
frequency in an acceptable format for passing to C<Config::Crontab>. By default
this defaults to a daily entry at random values for the hour and minute.

The randomness of these values is subject to the implementation provided by
C<Cpanel::Update::Crontab::get_random_hr_and_min>. See the documentation for
that method for details on how the hour and minute values are generated.

=cut

use cPstrict;

use Cpanel::Autodie          ();
use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::Update::Crontab  ();

sub _COMMAND {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

sub _CRON_FILE {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

sub _get_crontab_hour_minute_opts {

    my ( $hour, $minute ) = Cpanel::Update::Crontab::get_random_hr_and_min();
    return ( -minute => $minute, -hour => $hour );
}

=head2 $entry = __PACKAGE__->get_entry()

Gets the current crontab entry.

=over

=item Input

None

=item Output

Returns the Config::Crontab::Event representation of the crontab
entry that will run the command or undef if there is no cron entry.

=back

=cut

sub get_entry ($obj_or_class) {
    my $entry;

    if ( Cpanel::Autodie::exists( $obj_or_class->_CRON_FILE() ) ) {
        require Config::Crontab;
        my $ct = Config::Crontab->new( -file => $obj_or_class->_CRON_FILE(), -system => 1 );
        ($entry) = $ct->select();
    }

    return $entry;
}

=head2 __PACKAGE__->ensure_that_entry_exists()

Creates the crontab entry if it is not already present.

=over

=item Input

None

=item Output

=over

Returns 1 if the cron entry was created, 0 if it was already there, die on error.

=back

=back

=cut

sub ensure_that_entry_exists ($obj_or_class) {

    require Config::Crontab;
    my $event = Config::Crontab::Event->new(
        $obj_or_class->_get_crontab_hour_minute_opts(),
        -user    => 'root',                      #apparently needed for cron.d?
        -command => $obj_or_class->_COMMAND(),
    );

    #It won’t work to write *just* the Event object to the cron.d file
    #because cron expects a trailing newline, which Event->dump() doesn’t
    #include. For the sake of “completeness”, then, we’ll let Block handle
    #the formatting.
    my $block = Config::Crontab::Block->new();
    $block->first($event);

    Cpanel::FileUtils::Write::overwrite( $obj_or_class->_CRON_FILE(), $block->dump() );

    return 1;
}

=head2 __PACKAGE__->delete_entry()

Removes any existing crontab.

=over

=item Input

None

=item Output

Returns 1 if the cron entry was removed, 0 if it wasn't there, dies on error.

=back

=cut

sub delete_entry ($obj_or_class) {
    return Cpanel::Autodie::unlink_if_exists( $obj_or_class->_CRON_FILE() );
}

1;
