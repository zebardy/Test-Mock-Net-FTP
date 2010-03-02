package Test::Mock::Net::FTP;
use strict;
use warnings;
 
use File::Copy;
use File::Spec::Functions qw( catdir splitdir rootdir catfile curdir rel2abs abs2rel );
use File::Basename;
use Test::Mock::Log;
use Cwd qw(getcwd);
use Carp;
 
 
=head1 NAME
 
Test::Mock::Net::FTP - Mock Object for Net::FTP
 
=head1 SYNOPSIS
 
write synopsis here
 
=head1 DESCRIPTION
 
Test::Mock::Net::FTP is Mock Object for Net::FTP. This module behave like FTP servers, but only use local filesystem.(not using socket).
 
=cut
 
my %mock_server;
my $test_mock_ftp_log = Test::Mock::Log->new();
 
 
=head1 METHODS
 
=cut
 
=head2 mock_prepare
 
prepare FTP server in your local filesystem.
 
=cut
 
sub mock_prepare {
    my %args = @_;
    %mock_server = %args;
}
 
=head2 new
 
create new instance
 
=cut
 
sub new {
    my $class = shift;
    my ( $host, %opts ) = @_;
    return if ( !exists $mock_server{$host} );
 
    my $self = {
        mock_host => $host,
        mock_phisical_root => "",
        mock_server_root => "",
#        call_log => Test::Mock::Log->new(),
    };
    bless $self,$class;
    return $self
}
 
=head2 login
 
login mock FTP server

=cut
 
sub login {
    my $self = shift;
    my ( $user, $pass ) = $self->_record_args("login",@_);
    if ( $self->_mock_login_auth( $user, $pass) ) {# auth success
        $self->{mock_cwd} = rootdir();
        my $mock_server_for_user = $mock_server{$self->{mock_host}}->{$user};
        $self->{mock_phisical_root} = rel2abs($mock_server_for_user->{dir}->[0]) if defined $mock_server_for_user->{dir}->[0];
        $self->{mock_server_root} = $mock_server_for_user->{dir}->[1] if defined $mock_server_for_user->{dir}->[1];
        return 1;
    }
    $self->{message} = 'Login incorrect.';
    return;
}
 
sub _mock_login_auth {
    my $self = shift;
    my ( $user, $pass ) = @_;
    my $server_user = $mock_server{$self->{mock_host}}->{$user};
    return if !defined $server_user; #user not found
    my $server_password = $server_user->{password};
    return $server_password eq $pass;
}
 
 
=head2 pwd
 
return (mock) server current directory
 
=cut
 
sub pwd {
    my $self = shift;
    $self->_record_args("pwd",@_);
    return catdir($self->{mock_server_root}, $self->_mock_cwd);
}
 
 
=head2 mock_pwd
 
mock's current directory
 
=cut
 
sub mock_pwd {
    my $self = shift;
    return catdir(abs2rel($self->{mock_phisical_root}), $self->_mock_cwd);
}
 
 
=head2 cwd
 
change (mock) server current directory
 
=cut
 
sub cwd {
    my $self = shift;
    my ( $dirs ) = $self->_record_args("cwd",@_);
 
    if ( !defined $dirs ) {
        $self->{mock_cwd} = rootdir();
        $dirs = "";
    }
 
    my $backup_cwd = $self->_mock_cwd;
    for my $dir ( splitdir($dirs) ) {
        $self->_mock_cwd_each($dir);
    }
    $self->{mock_cwd} =~ s/^$self->{mock_server_root}//;#for absolute path
    return $self->_mock_check_pwd($backup_cwd);
}
 
sub _mock_cwd_each {
    my $self = shift;
    my ( $dir ) = @_;
    if ( $dir eq '..' ) {
        $self->{mock_cwd} = dirname($self->_mock_cwd);# to updir
    }
    else {
        $self->{mock_cwd} = catdir($self->_mock_cwd, $dir);
    }
}
 
# check if mock server directory "phisically" exists.
sub _mock_check_pwd {
    my $self = shift;
    my( $backup_cwd ) = @_;
    if ( ! -d $self->mock_pwd ) {
        $self->{mock_cwd} = $backup_cwd;
        $self->{message} = 'Failed to change directory.';
        return 0;
    }
    return 1;
}
 
=head2 put
 
put a file to mock FTP server
 
=cut
 
sub put {
    my $self = shift;
    my ( $local_file, $remote_file ) = $self->_record_args("put",@_);
    $remote_file = basename($local_file) if ( !defined $remote_file );
    copy( $self->_abs_local_file($local_file),
          $self->_abs_remote_file($remote_file) ) || croak "can't put $local_file to $remote_file\n";
}
 
=head2 get
 
get file from mock FTP server
 
=cut
 
sub get {
    my $self = shift;
    my ( $remote_file, $local_file ) = $self->_record_args("get",@_);;
    $local_file = basename($remote_file) if ( !defined $local_file );
    copy( $self->_abs_remote_file($remote_file),
          $self->_abs_local_file($local_file) ) || croak "can't get $remote_file\n";
}
 
 
=head2 ls
 
list file(s) in server directory.
 
=cut
 
sub ls {
    my $self = shift;
    my ( $dir ) = $self->_record_args("ls",@_);;
    my $target_dir = $self->_remote_dir_for_dir($dir);
    my @ls = split(/\n/, `ls $target_dir`);
    my @res = (defined $dir)? map{ catfile($dir, $_) } @ls : @ls;
    return \@res;
}

=head2 binary

change transfer mode to binary. This just records that binary mode was requested, 
it doesn't effect the simulated file transfer mechanism.

=cut

sub binary {
    my $self = shift;
    $self->_record_args("binary",@_);
    return 1;
}
 
 
=head2 dir
 
list file(s) with detail information(ex. filesize) in server directory.
 
=cut
 
sub dir {
    my $self = shift;
    my ( $dir ) = $self->_record_args("dir",@_);
    my $target_dir = $self->_remote_dir_for_dir($dir);
    my @dir = split(/\n/, `ls -l $target_dir`);
    shift @dir if ( $dir[0] !~ /^[-rxwtTd]{10}/ ); #remove like "total xx"
    return @dir;
}
 
sub _remote_dir_for_dir {
    my $self = shift;
    my($dir) = @_;
    $dir =~ s/^$self->{mock_server_root}// if (defined $dir && $dir =~ /^$self->{mock_server_root}/ ); #absolute path
    $dir = "" if !defined $dir;
    return catdir($self->mock_pwd, $dir);
}
 
sub _remote_dir_for_file {
    my $self = shift;
    my( $remote_file ) = @_;
    my $remote_dir = dirname(catfile($self->{mock_cwd},$remote_file));
    #my $remote_dir = (dirname( $remote_file ) eq curdir()) ? $self->{mock_cwd} : dirname( $remote_file ) ;
    $remote_dir =~ s/^$self->{mock_server_root}// if ( $remote_file =~ /^$self->{mock_server_root}/ );
    return $remote_dir;
}
 
sub _abs_remote_file {
    my $self = shift;
    my( $remote_file ) = @_;
    my $remote_dir = $self->_remote_dir_for_file($remote_file);
    $remote_dir = "" if !defined $remote_dir;
    return catfile($self->{mock_phisical_root}, $remote_dir, basename($remote_file))
}
 
sub _abs_local_file {
    my $self = shift;
    my ($local_file) = @_;
    my $root = rootdir();
    return $local_file if ( $local_file =~ m{^$root} );
    my $local_dir = dirname( $local_file ) eq curdir() ? getcwd() : dirname( $local_file );
    $local_dir = "" if !defined $local_dir;
    return catfile($local_dir, basename($local_file));
}
 
=head2 message
 
return messages from mock FTP server
 
=cut
 
sub message {
    my $self = shift;
    push @{$test_mock_ftp_log->{call_log}},["message"];
    return $self->{message};
}
 
sub _mock_cwd {
    my $self = shift;
    return (defined $self->{mock_cwd}) ? $self->{mock_cwd} : "";
}
 
=head2 close
 
close connection mock FTP server.(eventually do nothing)
 
=cut
 
sub close {
    my $self = shift;
    push @{$test_mock_ftp_log->{call_log}},["close"];
    return 1;
}

=head2 get_log

Get the function call log (this will clear the log).

=cut

sub get_log {
#    my $self = shift;
#    my $log = $self->{call_log};
#    $self->clear();
    my $log = $test_mock_ftp_log; 
    clear();
    return $log;
}

=head2 next_call

Similar to Test::MockObject, this will return the name and argument list of the next method called.

=cut

sub next_call {
#    my $self = shift;
#    return $self->{call_log}->next_call(shift);
    $test_mock_ftp_log->next_call(shift);
}

=head clear

Clears the internal record of all method calls.

=cut

sub clear {
#    my $self = shift;
#    $self->{call_log} = Test::Mock::Log->new();
    $test_mock_ftp_log = Test::Mock::Log->new();
}

sub _record_args {
    my $self = shift;
    my $call = shift;
    my @args = @_;
#    push @{$self->{call_log}->{call_log}},[$call,\@args];
    push @{$test_mock_ftp_log->{call_log}},[$call,\@args];
    return @args;
}

 
sub import {
    my ($package, @args) = @_;
    for my $arg ( @args ) {
        _mock_intercept() if ( $arg eq 'intercept' );
    }
}
 
sub _mock_intercept {
    use Net::FTP;
    no warnings 'redefine';
    *Net::FTP::new = sub {
        my $class = shift;#discard $class
        return Test::Mock::Net::FTP->new(@_);
    }
}
 
sub AUTOLOAD {
    our $AUTOLOAD;
    (my $method = $AUTOLOAD) =~ s/.*:://s;
    carp "Not Impremented method $method called.";
}
 
sub DESTROY {}
 
1;
 
 
=head1 AUTHOR
 
Takuya Tsuchida E<lt>takuya.tsuchida@gmail.comE<gt>
 
=head1 SEE ALSO
 
Net::FTP
 
=head1 REPOSITORY
 
plan to put sources on github or coderepos
 
=head1 LICENSE
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
 
=cut
