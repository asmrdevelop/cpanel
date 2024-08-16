package Cpanel::ApiInfo::Writer;

# cpanel - Cpanel/ApiInfo/Writer.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base qw(
  Cpanel::ApiInfo
);

use Cpanel::SafeDir::MK             ();
use Cpanel::Transaction::File::JSON ();

sub verify {
    my ($self) = @_;

    my $file_path = $self->SPEC_FILE_PATH();

    my $dir = $file_path;
    $dir =~ s{/[^/]+\z}{};

    Cpanel::SafeDir::MK::safemkdir($dir) or die $!;

    my $transaction = Cpanel::Transaction::File::JSON->new(
        path        => $file_path,
        permissions => 0644,
    );

    my $need_update = $self->_update_transaction($transaction);

    if ($need_update) {
        my ( $save_ok, $save_err ) = $transaction->save();
        die $save_err if !$save_ok;
    }

    my ( $close_ok, $close_err ) = $transaction->close();
    die $close_err if !$close_ok;

    return $need_update;
}

1;
