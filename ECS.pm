## no critic signatures
package ECS;
our $VERSION = '0.1';
use v5.38;
use Object::Pad;

class ECS
{
    field %event_registry;

    method dispatch_event ($name, @args)
    {
        for my $func ($event_registry{$name}->@*)
        {
            $func->(@args);
        }
    }

    method _make_callback ($name)
    {
        return sub ($weak_method)
        {
            my $index = 0;
            for my $func ($event_registry{$name}->@*)
            {
                if ($func == $weak_method)
                {
                    splice($event_registry{$name}->@*, $index, 1);
                    last;
                }
                $index++;
            }
            delete $event_registry{$name}
                unless $event_registry{$name}->@*;
        }
    }

    method set_handler ($name, $func)
    {
        $event_registry{$name} //= [];
        if (ref($func) eq 'CODE')
        {
            push($event_registry{$name}->@*, $func);
        }
        elsif (ref($func) eq 'ARRAY')
        {
            for my $f ($func->@*)
            {
                push($event_registry{$name}->@*, $f)
                     if ref($f) eq 'CODE';
            }
        }
    }

    method remove_handler ($name, $func)
    {
        my $index = 0;
        for my $f ($event_registry{$name}->@*)
        {
            if ($f == $func)
            {
                splice($event_registry{$name}->@*, $index, 1);
                last;
            }
            $index++;
        }
        delete $event_registry{$name}
             unless $event_registry{$name}->@*;
    }
}

package ECS::Processor;

use Object::Pad;

role ECS::Processor
{
    field $priority :accessor :param=0;

    method process;
}

package ECS::World;

use Object::Pad;

class ECS::World
{
    use List::Util qw(any first);
    use builtin qw(true false blessed);
    no warnings qw(experimental::builtin);
    field $current_context :param="default";
    field $entity_count :param=1;
    field %components;
    field %entities;
    field %dead_entities;
    field %component_cache;
    field %components_cache;
    field @processors;
    field %process_times;

    method clear_cache ()
    {
        %component_cache = ();
        return
    }

    method clear_database ()
    {
        $entity_count = 1;
        %components = ();
        %entities = ();
        %dead_entities = ();
        $self->clear_cache();
        return
    }

    method add_processor ($processor, $priority=undef)
    {
        $processor->priority( $priority // $processor->priority() // 0 );

        push @processors, $processor;
        @processors = sort { $b->{priority} <=> $a->{priority} } @processors;
        return
    }

    method remove_processor ($processor_type)
    {
        @processors = grep { ref($_) ne $processor_type } @processors;
        return
    }

    method get_processor ($processor_type)
    {
        return first { ref($_) eq $processor_type } @processors
    }

    method create_entity (@components)
    {
        my $entity = $entity_count++;
        for my $component (@components)
        {
            my $type = ref($component);
            $components{$type}{$entity} = $component;
            $entities{$entity}{$type} = $component;
            $self->clear_cache();
        }
        return $entity;
    }

    method delete_entity ($entity, $immediate=false)
    {
        if ($immediate)
        {
            for my $type (keys $entities{$entity}->%*)
            {
                delete $components{$type}{$entity};
                delete $components{$type}
                    unless $components{$type}->%*;
            }
            delete $entities{$entity};
            $self->clear_cache();
        }
        else {
            $dead_entities{$entity} = 1;
        }
        return
    }

    method entity_exists ($entity)
    {
        return exists $entities{$entity} && !exists $dead_entities{$entity};
    }

    method component_for_entity ($entity, $type)
    {
        return $entities{$entity}{$type};
    }

    method components_for_entity ($entity)
    {
        return values $entities{$entity}->%*
    }

    method has_component ($entity, $type)
    {
        return exists $entities{$entity}{$type}
    }

    method has_components ($entity, @types)
    {
        return any { exists $entities{$entity}{$_} } @types
    }

    method add_component ($entity, $component, $type_alias=undef)
    {
        my $type = $type_alias // ref($component);
        $components{$type} //= {};
        $components{$type}{$entity} = $component;
        $entities{$entity}{$type} = $component;
        $self->clear_cache();
        return
    }

    method remove_component ($entity, $type)
    {
        delete $components{$type}{$entity};
        delete $components{$type}
            unless $components{$type}->%*;
        $self->clear_cache();
        return delete $entities{$entity}{$type}
    }

    method _get_component ($type)
    {
        return
            map { ($_ => $entities{$_}{$type}) }
            keys $components{$type}->%*;
    }

    method _get_components (@types)
    {
        return
            map { my $en = $_; ( $en => [ map { $entities{$en}{$_} } @types ] ) }
            grep { $self->has_components($_, @types) }
            map { keys $components{$_}->%* }
            @types;
    }

    method get_component ($type)
    {
        return
            $component_cache{$type} //= [
                sort { $a <=> $b }
                $self->_get_component($type)
            ];
    }

    method get_components (@types)
    {
        my $key = join('-', sort @types);

        $components_cache{$key} //=
            [ sort { $a <=> $b } $self->_get_components(@types) ];

        return $components_cache{$key}
    }

    method try_component ($entity, $type)
    {
        return $entities{$entity}{$type}
            if $entities{$entity};

        return
    }

    method try_components ($entity, @types)
    {
        for my $type (@types)
        {
            return unless exists $entities{$entity}{$type};
        }
        return map { $entities{$entity}{$_} } @types;
    }

    method clear_dead_entities ()
    {
        for my $entity (keys %dead_entities)
        {
            for my $type (keys %{$entities{$entity}})
            {
                delete $components{$type}{$entity};
                delete $components{$type}
                    unless $components{$type}->%*;
            }
            delete $entities{$entity};
        }
        %dead_entities = ();
        $self->clear_cache();

        return
    }

    method process ()
    {
        $self->clear_dead_entities();
        for my $processor (@processors)
        {
            $processor->process();
        }

        return
    }

    method timed_process ()
    {
        $self->clear_dead_entities();
        for my $processor (@processors)
        {
            my $start_time = time();
            $processor->process();
            $process_times{ref($processor)} = int((time() - $start_time) * 1000);
        }

        return
    }

    method list_worlds ()
    {
        return keys %entities
    }

    method delete_world ($name)
    {
        die "The active World context cannot be deleted."
            if $current_context eq $name;

        return delete $entities{$name}
    }

    method switch_world ($name)
    {
        if (!exists $entities{$name})
        {
            $entities{$name} = {};
            $components{$name} = {};
            @processors = ();
            $process_times{$name} = {};
        }
        $current_context = $name;
    }

    method current_world ()
    {
        return $current_context;
    }
}

1;
