package Cpanel::Binaries::Cmd::Response;

# cpanel - Cpanel/Binaries/Cmd/Response.pm         Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::SafeRun::Extra';

use Simple::Accessor qw{
  data
  error
};

sub success ($self) {
    return length $self->error ? 0 : 1;
}

# we should prefer is_success which is the Mojo standard
*is_success = *success;

# Consolidated output.
sub output ($self) {
    my $str = $self->stdout // '';
    my $err = $self->stderr // '';
    if ( length $err ) {
        chomp $str;
        $str .= "\n" if length $str;
        $str .= $err;
    }
    return $str;
}

sub has_success ($self) {

    # already failed
    return $self unless $self->success;

    my $output = $self->output // '';

    if ( $output !~ qr{^Success:}m ) {
        $self->error( $output || 'Missing Success from reply output.' );
    }

    return $self;
}

sub has_no_warnings ($self) {

    if ( $self->success ) {
        my $output = $self->output // '';
        if ( $output =~ qr{^Warning:}m ) {
            $self->error($output);
        }
    }

    return $self;
}

1;
