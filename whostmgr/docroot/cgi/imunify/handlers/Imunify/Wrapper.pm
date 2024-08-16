package Imunify::Wrapper;

use strict;
use warnings FATAL => 'all';
use Encode;
use Data::Dumper;
use File::HomeDir;
use File::Basename;
use IO::Handle;

use Imunify::Exception;
use Imunify::Render;
use Imunify::Utils;
use Imunify::Config;
use Cpanel::JSON;

#use CGI::Carp qw(fatalsToBrowser); # uncomment to debug 500 error

sub execute {
    my ($request, $isWHM) = @_;
    my %data = ();

    $data{'command'} = \@{$request->{'method'}};
    $data{'params'} = $request->{'params'};
    $data{'params'}{'remote_addr'} = $ENV{REMOTE_ADDR};

    return Imunify::Utils::execute('execute', \%data, $isWHM);
}

sub request {
    my ($request, $isWHM) = @_;
    my $response = execute($request, $isWHM);
    Imunify::Render::JSONHeader(Imunify::Render->HTTP_STATUS_OK);
    print $response;
}

sub imunfyEmailRequest {
    my ($request, $isWHM) = @_;
    my %data = ();
    $data{'username'} = $ENV{REMOTE_USER};
    $data{'command'} = \@{$request->{'method'}};
    $data{'params'} = $request->{'params'};
    my $response = Imunify::Utils::execute('imunifyEmail', \%data, $isWHM);
    Imunify::Render::JSONHeader(Imunify::Render->HTTP_STATUS_OK);
    print $response;
}

sub upload {
    my ($cgi, $isWHM) = @_;
    my ($tmpPath);
    my %data = (
        'files' => {},
    );

    foreach my $file ($cgi->param('files[]')) {
        $tmpPath = $cgi->tmpFileName($file);
        $data{'files'}{$tmpPath} = "$file";
    }

    return Imunify::Utils::execute('uploadFile', \%data, $isWHM);
}

1;
