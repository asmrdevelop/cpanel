package Cpanel::PAM;

# cpanel - Cpanel/PAM.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PAM

=head1 SYNOPSIS

    my $limits = Cpanel::PAM::get_user_limits('johnny');

    # Do this as root.
    $limits->restore_greater_rlimits();

    # ...

    # Do this as the user (probably).
    $limits->restore();

=head1 DESCRIPTION

This module deals with L<http://www.linux-pam.org/|PAM>.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile::ReadFast ();
use Cpanel::Autodie            ();
use Cpanel::ForkAsync          ();

use constant _PAM_SERVICE => 'login';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $limits_obj = get_user_limits( $USERNAME )

Returns a L<Cpanel::PAM::Limits> instance that records the process limits
of a PAM login session for $USERNAME.

If there is any error in reading the limits, a suitable exception
is thrown.

This function avoids the overhead that loading PAM via XS would normally
entail. One disadvantage of this approach is that the C<maxlogins> limit
is only observed if this function’s session creation fails because of
that limit.

=cut

sub get_user_limits {
    my ($username) = @_;

    die "Need username!" if !$username;

    die "Must be root!" if $>;

    local $!;

    my ( $pid, $rlimits_r, $err_r ) = _make_pam_child($username);

    # Use of a pipe to transmit the PAM limits from child to parent is
    # inefficient. An alternative would be to use prlimit in the parent,
    # but that wouldn’t be as accurate since the parent would somehow
    # have to ensure that the limits it gets from prlimit are actually
    # those that PAM has set, which is trickier.

    Cpanel::LoadFile::ReadFast::read_all_fast( $err_r, my $err = q<> );
    close $err_r;

    Cpanel::LoadFile::ReadFast::read_all_fast( $rlimits_r, my $rlim_txt = q<> );
    close $rlimits_r;

    my @rlim_lines = split m<\n>, $rlim_txt;

    my $prio    = shift @rlim_lines;
    my %rlimits = map { split m< >, $_, 2 } @rlim_lines;

    $_ && chomp for ( $prio, values %rlimits );

    local $?;
    waitpid $pid, 0;

    if ($?) {
        require Cpanel::ChildErrorStringifier;
        my $autopsy = Cpanel::ChildErrorStringifier->new($?)->autopsy();
        die "Failed to read “$username”’s PAM limits ($autopsy): $err";
    }
    elsif ($err) {
        warn "Reading “$username”’s PAM limits: $err";
    }

    $_ = [ split m< >, $_ ] for values %rlimits;

    return bless {
        priority => $prio,
        rlimits  => \%rlimits,
      },
      'Cpanel::PAM::Limits';
}

sub _make_pam_child {
    my ($username) = @_;

    pipe( my $rlimits_r, my $rlimits_w ) or die "pipe(): $!";
    pipe( my $err_r,     my $err_w )     or die "pipe(): $!";

    my $pid = Cpanel::ForkAsync::do_in_child(
        sub {
            open( \*STDERR, '>&=', $err_w ) or die "dup2 pipe to STDERR failed: $!";

            close $rlimits_r;
            close $err_r;
            close $err_w;

            require Authen::PAM;
            require Cpanel::Sys::Rlimit;

            my $pamh   = Authen::PAM->new( _PAM_SERVICE(), $username );
            my $status = _pam_open_session($pamh);

            if ( $status != Authen::PAM::PAM_SUCCESS() ) {
                die "Failed to open PAM session for “$username”: $status, " . $pamh->pam_strerror($status);
            }

            $status = _pam_close_session($pamh);
            if ( $status != Authen::PAM::PAM_SUCCESS() ) {
                warn "Failed to close PAM session for “$username”: $status, " . $pamh->pam_strerror($status);
            }

            my $out = getpriority( 0, 0 ) . "\n";

            for my $name ( keys %Cpanel::Sys::Rlimit::RLIMITS ) {
                my @cur_max = Cpanel::Sys::Rlimit::getrlimit($name);
                $out .= "$name @cur_max\n";
            }

            Cpanel::Autodie::syswrite_sigguard( $rlimits_w, $out );

            close $rlimits_w;
        }
    );

    close $rlimits_w;
    close $err_w;

    return ( $pid, $rlimits_r, $err_r );
}

# For mocking in tests.
sub _pam_open_session  { return $_[0]->pam_open_session() }
sub _pam_close_session { return $_[0]->pam_close_session() }

#----------------------------------------------------------------------

package Cpanel::PAM::Limits;

=head1 NAME

Cpanel::PAM::Limits

=head1 DESCRIPTION

This class is not meant to be instantiated directly.

=head1 FUNCTIONS

=head2 I<OBJ>->restore()

Sets the process to the limits stored in I<OBJ>.

=cut

sub restore {
    my ($self) = @_;

    require Cpanel::Sys::Rlimit;

    $self->_for_each_rlimit( \&Cpanel::Sys::Rlimit::setrlimit );

    local ( $!, $@ );

    setpriority( 0, 0, $self->{'priority'} ) or warn "setpriority(0, 0, $self->{'priority'}): $!";

    return;
}

=head2 I<OBJ>->restore_greater_rlimits()

This restores those rlimits that exceed the current process’s rlimits.
This is necessary if the current process is running as root but the rlimits
are to be restored later as the user: the saved rlimits might exceed the
current process’s rlimits, and if we attempt to restore the saved rlimits
as the user in that case we’ll get ugly EPERM errors because that requires
the CAP_SYS_RESOURCE capability, which unprivileged processes don’t normally
have.

To guard against this problem, call this function as root,
probably immediately after you read the limits.

=cut

sub restore_greater_rlimits {
    my ($self) = @_;

    require Cpanel::Sys::Rlimit;

    $self->_for_each_rlimit(
        sub {
            my ( $name, undef, $pam_hard ) = @_;

            my ( $cur_soft, $cur_hard ) = Cpanel::Sys::Rlimit::getrlimit($name);

            if ( $pam_hard > $cur_hard ) {
                Cpanel::Sys::Rlimit::setrlimit( $name, $cur_soft, $pam_hard );
            }
        },
    );

    return;
}

sub _for_each_rlimit {
    my ( $self, $todo_cr ) = @_;

    local ( $!, $@ );

    my $rlimits_hr = $self->{'rlimits'};

    $todo_cr->( $_, @{ $rlimits_hr->{$_} } ) for keys %$rlimits_hr;

    return;
}

#----------------------------------------------------------------------

1;
