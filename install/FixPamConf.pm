package Install::FixPamConf;

# cpanel - FixPamConf.pm
#                                                   Copyright 2022 cPanel L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::Autodie ();
use Try::Tiny;

our $VERSION = '1.0';

=head1 DESCRIPTION

    Perform necessary PAM configuration changes.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

our @files = qw {
  /etc/pam.d/chsh
  /etc/pam.d/chfn
};

our @shells = qw {
  /usr/local/cpanel/bin/jailshell
  /usr/local/cpanel/bin/noshell
};

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('fixpamconf');

    return $self;
}

sub perform {
    my $self = shift;

    for my $file (@files) {
        try {
            _insert_conf_lines( $file, \@shells );
        }
        catch {
            warn "Failed to edit PAM configuration in file '$file': $_";
        };
    }

    return 1;
}

sub _insert_conf_lines {
    my ( $file, $shells ) = @_;

    Cpanel::Autodie::open( my $ifh, '<', $file );
    my @lines = <$ifh>;
    Cpanel::Autodie::close($ifh);

    for my $shell ( @{$shells} ) {
        my $re = qr{^account\s+required\s+pam_succeed_if\.so(?:\s+debug)?\s+shell\s+!=\s+\Q$shell\E$};

        if ( !defined( _find_pattern_index( \@lines, $re ) ) ) {
            my $i = _find_pattern_index( \@lines, qr{^account\s+} ) // scalar(@lines);
            splice @lines, $i, 0, "account\trequired\tpam_succeed_if.so\tshell != $shell\n";
        }
    }

    Cpanel::Autodie::open( my $ofh, '>', $file );

    for my $line (@lines) {
        Cpanel::Autodie::print( $ofh, $line );
    }

    Cpanel::Autodie::close($ofh);

    return;
}

sub _find_pattern_index {
    my ( $lines, $pattern ) = @_;

    for my $i ( 0 .. $#{$lines} ) {
        if ( $lines->[$i] =~ /$pattern/ ) {
            return $i;
        }
    }

    return undef;
}

1;

__END__
