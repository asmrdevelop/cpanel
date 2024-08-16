package Cpanel::Update::Blocker::Base;

# cpanel - Cpanel/Update/Blocker/Base.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::iContact         ();
use Cpanel::FileUtils::Open  ();
use Cpanel::LoadModule       ();
use Cpanel::Hostname         ();
use Cpanel::Update::Config   ();
use Cpanel::Update::Logger   ();
use Cpanel::Version::Compare ();

=head1 NAME

Cpanel::Update::Blocker::Base - Provides the common code used to signal upgrade blocking to the update system.

=head1 DESCRIPTION

This is a parent class of Cpanel::Update::Blocker. It provides the following methods for the child class:

new, logger, block_version_change, is_fatal_block, delay_upgrade, generate_blocker_file

=head1 METHODS

=over

=item B<new>

Call this before blocker checks to initialize the objects.

Needs: starting_version, target_version, upconf_ref
Probably should also pass in a logger.

=cut

sub update_blocks_fname {
    return '/var/cpanel/update_blocks.config';
}

sub new {
    my ( $class, $self ) = @_;

    die("Unexpected class passed to new for Cpanel::Update::Blocker.") unless $class && $class eq 'Cpanel::Update::Blocker';
    die("Options hash ref not passed to new")                          unless $self  && ref($self) eq 'HASH';

    $self->{'logger'} ||= Cpanel::Update::Logger->new();
    $self->{'starting_version'} or die("Must be passed starting_version to do blocker calculations");
    $self->{'target_version'}   or die("Must be passed target_version to do blocker calculations");
    $self->{'upconf_ref'}       or die("Need upconf_ref to do blocker calculations");

    $self->{'is_fatal_block'} = 0;

    $self = bless $self, $class;

    $self->{'messages'} = [];

    return $self;
}

sub upgrade_deferred_file {
    return '/var/cpanel/upgrade_deferred';
}

sub starting_version ($self) {
    return $self->{'starting_version'};
}

sub target_version ($self) {
    return $self->{'target_version'};
}

=item B<logger>

Helper function to ease logging in subroutines below.

=cut

sub logger {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    return $self->{'logger'};
}

=item B<block_version_change>

Bumps a fatal counter. Logs the message as a blocker. If not quiet, tracks the list of failures for later blocker file creation.

=cut

sub block_version_change {
    my ( $self, $message, $severity, $notify ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    return unless $message;

    $severity //= 'fatal';
    $notify   //= 1;

    # Push the message into the list.
    if ( $severity !~ m/quiet/i ) {
        push( @{ $self->{'messages'} }, { 'message' => $message, 'severity' => $severity, 'notify' => $notify } );
    }

    # Remove URL from log output so it just goes to the blocker file.
    $message =~ s/<a.*?>//ig;
    $message =~ s{</a>}{}ig;
    $message =~ s{&reg;}{®}g;    # Convert the HTML directive to a raw UTF-8 char.

    $self->logger->error("Blocker found: $message");

    # Determine if this is a warning or a fatal blocker.
    $self->{'is_fatal_block'}++;

    return $self->{'is_fatal_block'};
}

=item B<is_fatal_block>

Helper used to report if this object has found a fatal blocker. Also allows change of this value.

=cut

sub is_fatal_block {
    my ( $self, $new_value ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    if ( defined $new_value ) {
        $self->{'is_fatal_block'} = $new_value;
    }

    return $self->{'is_fatal_block'};
}

=item B<delay_upgrade>

Delay upgrades by up to 10 business days
using a touch file with future mtime.

This subroutine only applies to stable or release tiers.

=cut

sub delay_upgrade {
    my ($self) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    if ( $self->is_fatal_block ) {
        return 10;
    }

    # Force just ignores the delays.
    return 1 if $self->{'force'};

    # Do not delay unless not running interactively.
    return 2 unless $ENV{'CPANEL_IS_CRON'};

    # We only want to enforce delays on release tier.
    my $current_tier = Cpanel::Update::Config::get_tier( $self->{'upconf_ref'} );
    return 3 unless lc($current_tier) eq 'release';

    # Do not block unless target_version matches our tier (release, stable or lts)
    return 5 unless $self->{'tiers'}->is_slow_rollout_tier( $self->{'target_version'} );

    # We only want to delay if this is a change to a newer major version.
    my $target_major   = Cpanel::Version::Compare::get_major_release( $self->_Target_version() )    or return 21;    # Pretty sure return 21
    my $starting_major = Cpanel::Version::Compare::get_major_release( $self->{'starting_version'} ) or return 22;    # and return 22 can't happen.
    return 20 if $starting_major eq $target_major;

    my $touchfile = $self->upgrade_deferred_file;

    # The shift is for testing purposes to force a non 0 value with rand
    my $mtime = ( stat($touchfile) )[9];

    # If touchfile is in the past, don't block
    return 6 if $mtime && $mtime < time;

    if ( !$mtime ) {
        $mtime = $self->_get_future_upgrade_date();
        return 7 if !$mtime;    # we are not delayed
        $self->_alter_mtime( $touchfile, $mtime );
    }

    $self->block_version_change( "Upgrade to the next $target_major build is blocked in order to gradually distribute upgrades over multiple days. If you wish to upgrade now, you can do so by executing ‘/usr/local/cpanel/scripts/upcp --force’ via SSH or ‘WHM → Home → Server Configuration → Terminal’", 'info', 0 );

    return 8;                   # the only meaningful return code...
}

# “protected” method
sub _Target_version ($self) {
    return $self->{'target_version'};
}

sub generate_blocker_file {
    my ( $self, $notify ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    # Something's wrong if this return is triggered.
    return unless $self->{'messages'} && ref( $self->{'messages'} ) eq 'ARRAY';

    my @messages            = @{ $self->{'messages'} };
    my $update_blocks_fname = $self->update_blocks_fname;

    if ( !@messages ) {
        if ( -e $update_blocks_fname ) {
            unlink($update_blocks_fname) or $self->logger->error("Unable to unlink $update_blocks_fname");
        }
        return;
    }

    ## using a simple to parse text file, as we can not assume JSON::Syck is available
    ##   at this point
    open( my $fh, '>', $update_blocks_fname )
      or die("Unable to open $update_blocks_fname");

    my $message = join( "\n", map { "$_->{'severity'},$_->{'message'}" } @messages );
    print {$fh} $message;
    close($fh);

    $notify &&= grep { $_->{'notify'} } @messages;

    if ($notify) {

        # It is possible that Cpanel::iContact::Class::Update::Blocker
        # may not yet be available as this could be running as a .static
        # file on a previous version of cPanel.  If so we need to fallback
        # to using the legacy version.
        if ( try { Cpanel::LoadModule::load_perl_module('Cpanel::iContact::Class::Update::Blocker') } ) {

            # Remove URL from log output so it just goes to the blocker file.
            my @notifications;
            foreach (@messages) {
                ( my $message_sanitized = $_->{'message'} ) =~ s{<\/?a.*?>}{}ig;
                push @notifications, { 'severity' => $_->{'severity'}, 'message' => $message_sanitized };
            }
            $self->_send_icontact_class_notification(
                'class'            => 'Update::Blocker',
                'application'      => 'Update::Blocker',
                'constructor_args' => [
                    'origin'           => 'upcp',
                    'host'             => Cpanel::Hostname::gethostname(),
                    'messages'         => \@notifications,
                    'starting_version' => $self->{'starting_version'},
                    'target_version'   => $self->{'target_version'},
                ]
            );
        }
        else {

            # Remove URL from log output so it just goes to the blocker file.
            $message =~ s{<\/?a.*?>}{}ig;
            my $subject = "cPanel version change from “$self->{'starting_version'}” to “$self->{'target_version'}” is blocked";
            $self->_send_icontact_noclass_notification( $subject, $message );

        }

    }

    return 1;
}

=item B<_roll_100_die>

Simulate rolling a die with 100 faces...
Return a random value in the range [1..100]

=cut

sub _roll_100_die {    # random value from 1..100
    my ($self) = @_;

    die('This is a method call.') unless ref $self eq 'Cpanel::Update::Blocker';

    return int( rand(100) ) + 1;
}

=item B<update_speed>

Return one ArrayRef representing the dynamic adopted
for the update.

- the position in the array represents the day (index 0 is for today, index 1 for tomorrow, ... )
- the value is the percentage of customers allowed to perform the update on this day.

We are currently using a dynamic over 10 days, but this can be adjusted.

=cut

# the total sum should be == 100
sub update_speed {
    my ($self) = @_;

    die('This is a method call.') unless ref $self eq 'Cpanel::Update::Blocker';

    return [
        # day => % of customers
        1,     # day 0 -> +1% of customers can update
        2,     # day 1 -> +2%
        4,     # day 2 -> +4%
        6,     # day 3
        12,    # day 4
        15,    # day 5
        15,    # day 6
        15,    # day 7
        15,    # day 8
        15,    # day 9
    ];
}

=item B<update_in_n_days>

Returns a number between [0..N] where N is
the total number of days defined by L<update_speed>.

0 means update today
1 means update tomorrow...

=cut

sub update_in_n_days {
    my ($self) = @_;

    die('This is a method call.') unless ref $self eq 'Cpanel::Update::Blocker';

    # Let's roll a die first
    my $die = $self->_roll_100_die();

    my $update_speed = $self->update_speed();

    # let's check which day position we are going to
    my $day_pos     = 0;    # which day position we are going to
    my $total_pcent = 0;    # cumulate percentage

    foreach my $pcent (@$update_speed) {
        $total_pcent += $pcent;

        last if $die <= $total_pcent;
        ++$day_pos;
    }

    # safety for boundary limit
    if ( $day_pos >= scalar @$update_speed ) {
        $day_pos = scalar @$update_speed - 1;
    }

    return $day_pos;
}

=item B<_get_future_upgrade_date>

Returns the time (in seconds) of midnight today plus x business days

Can also return 'undef' when the update is not delayed and can occurs right now.

=cut

sub _get_future_upgrade_date {
    my ( $self, $now ) = @_;

    die('This is a method call.') unless ref $self eq 'Cpanel::Update::Blocker';

    my $update_speed = $self->update_speed();

    my $update_in_n_days = $self->update_in_n_days();

    $now ||= time();
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($now);

    # Reset to midnight
    $now = $now - $sec - $min * 60 - $hour * 60 * 60;

    # add some extra days
    my $ten_first_days = $self->_get_first_valid_ndays( scalar @$update_speed, $wday );

    # want to update today and today is not delayed
    if ( $update_in_n_days == 0 && $ten_first_days->[0] == 0 ) {

        # this is our lucky day, we can proceed to the update
        #   we are in the very first day slot which is a valid day [no offset]
        return;
    }

    my $one_day = 86400;

    # we would like to perform the update in `$update_in_n_days` days
    #   but we need to take into account that some weekday are not valid
    #   so we are shifting the value to avoid weekends [Friday included]
    $now += $one_day * $ten_first_days->[$update_in_n_days];

    return $now;
}

=item B<_get_first_valid_ndays( $ndays, $wday )>

Returns one ArrayRef of C<$ndays> elements, knowing that
today is the day of week C<$wday>

Day of Week use the L<time> definition: Sunday = 0, Monday = 1, ...]

The value in Nth position of the Array indicates in how
many days is the Nth valid day to perform an update.

This is used to avoid updates during Friday, Saturday and Sunday.

=cut

sub _get_first_valid_ndays {
    my ( $self, $ndays, $wday ) = @_;

    die('This is a method call.') unless ref $self eq 'Cpanel::Update::Blocker';
    die "NDays need to be > 0"    unless $ndays && $ndays > 0;

    # wday is the weekday
    # $wday is the day of the week, with 0 indicating Sunday and 3
    #   indicating Wednesday

    #my $MONDAY   = 1;
    my $FRIDAY   = 5;
    my $SATURDAY = 6;
    my $SUNDAY   = 0;

    die "Invalid wday" unless defined $wday && $SUNDAY <= $wday && $wday <= $SATURDAY;

    # $ndays: how many days do we want
    # $wday:  what day is the first day

    my @days;

    # counter
    my $c = 0;

    while (1) {

        # we are not accepting updates on Friday, Saturday and Sunday
        next if ( $wday == $FRIDAY || $wday == $SATURDAY || $wday == $SUNDAY );
        push @days, $c;

        # stop when we get 10 days value
        last if scalar @days == $ndays;
    }
    continue {
        # increments the counter and wday
        ++$c;
        $wday = ( $wday + 1 ) % 7;
    }

    return \@days;
}

=item B<_alter_mtime>

Alter touch file mtime to future time

=cut

sub _alter_mtime {
    my ( $self, $touchfile, $future ) = @_;
    ref $self eq 'Cpanel::Update::Blocker' or die('This is a method call.');

    die 'No touchfile'    if !$touchfile;
    die 'No future mtime' if !$future;

    Cpanel::FileUtils::Open::sysopen_with_real_perms(
        my $t_fh,
        $touchfile,
        'O_WRONLY|O_TRUNC|O_CREAT',
        0640
    ) or die "Cannot create touchfile $touchfile - $!";
    close $t_fh;
    utime( $future, $future, $touchfile ) or $self->logger->warning("Unable to set future mtime on $touchfile");

    return;
}

# separated to be able to be overridden during testing.
sub _send_icontact_class_notification {
    my ( $self, %notification_args ) = @_;

    require Cpanel::Notify;
    return Cpanel::Notify::notification_class(%notification_args);
}

sub _send_icontact_noclass_notification {
    my ( $self, $subject, $message ) = @_;

    return Cpanel::iContact::icontact(
        'application' => 'upcp',
        'subject'     => $subject,
        'message'     => $message,
    );
}

=back
=cut

1;
