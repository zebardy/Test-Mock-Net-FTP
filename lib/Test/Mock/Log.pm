package Test::Mock::Log;
use strict;
use warnings;

sub new {
    my $class = shift;
 
    my $self = {
        call_log => [],
    };
    bless $self, $class;
}

sub next_call {
    my $self = shift;
    my $index = shift||0;
    my $log = $self->{call_log};
    my $next_item;
    for (my $i=0;$i<=$index;$i++){
        $next_item = shift @{$self->{call_log}};
    }
    return (defined $next_item)? @$next_item : (undef,undef);
}

1;
