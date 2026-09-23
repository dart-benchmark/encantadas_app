import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/appointment.dart';
import '../models/transaction.dart';
import '../widgets/add_appointment_form.dart';

class TurnosScreen extends StatelessWidget {
  const TurnosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turnos'),
      ),
      body: ValueListenableBuilder<Box<Appointment>>(
        valueListenable: Hive.box<Appointment>('appointments').listenable(),
        builder: (context, box, _) {
          final appointments = box.values.toList().cast<Appointment>();
          
          // Sort appointments by date (newest first)
          appointments.sort((a, b) => b.dateTime.compareTo(a.dateTime));

          if (appointments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Aún no hay turnos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Presiona el botón + para agregar tu primer turno',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: appointments.length,
            itemBuilder: (context, index) {
              final appointment = appointments[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppointmentCard(appointment: appointment),
              );
            },
          );
        },
      ),
    );
  }
}

class AppointmentCard extends StatelessWidget {
  final Appointment appointment;

  const AppointmentCard({
    super.key,
    required this.appointment,
  });

  Future<void> _completeAppointment(BuildContext context) async {
    if (appointment.completed) return; // Prevent double completion

    try {
      // Update appointment as completed
      appointment.completed = true;
      await appointment.save();

      // Create transaction
      final transactionsBox = Hive.box<Transaction>('transactions');
      final transaction = Transaction(
        amount: appointment.price,
        date: appointment.dateTime,
        source: 'turno',
        clientName: appointment.clientName,
        serviceName: appointment.serviceName,
      );
      await transactionsBox.add(transaction);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Turno marcado como concretado - ${appointment.formattedPrice} ingresado',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al completar turno: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _editAppointment(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddAppointmentForm(appointment: appointment),
    );
  }

  Future<void> _deleteAppointment(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Eliminar este turno?'),
          content: Text(
            'Se eliminará el turno de "${appointment.clientName}" permanentemente. Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await appointment.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.delete, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Turno eliminado correctamente'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar turno: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      child: Container(
        decoration: appointment.completed
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 2,
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Client name and status row with action button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appointment.clientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: appointment.completed 
                            ? TextDecoration.lineThrough 
                            : null,
                        color: appointment.completed
                            ? theme.textTheme.titleMedium?.color?.withValues(alpha: 0.6)
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Three-dot menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: theme.iconTheme.color?.withValues(alpha: 0.7),
                      size: 20,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _editAppointment(context);
                      } else if (value == 'delete') {
                        _deleteAppointment(context);
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      if (!appointment.completed)
                        const PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.blue, size: 18),
                              SizedBox(width: 8),
                              Text('Editar'),
                            ],
                          ),
                        ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Eliminar'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  if (appointment.completed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('💖', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            'Concretado',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange, width: 1),
                          ),
                          child: Text(
                            'Pendiente',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _completeAppointment(context),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // DateTime
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: appointment.completed
                        ? theme.iconTheme.color?.withValues(alpha: 0.4)
                        : theme.iconTheme.color?.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appointment.formattedDateTime,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: appointment.completed
                          ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)
                          : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                      decoration: appointment.completed 
                          ? TextDecoration.lineThrough 
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Service
              Row(
                children: [
                  Icon(
                    Icons.design_services,
                    size: 16,
                    color: appointment.completed
                        ? theme.iconTheme.color?.withValues(alpha: 0.4)
                        : theme.iconTheme.color?.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appointment.serviceName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appointment.completed
                            ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5)
                            : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                        decoration: appointment.completed 
                            ? TextDecoration.lineThrough 
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Price
              Row(
                children: [
                  Icon(
                    Icons.attach_money,
                    size: 16,
                    color: appointment.completed
                        ? Colors.green.withValues(alpha: 0.7)
                        : theme.iconTheme.color?.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appointment.formattedPrice,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: appointment.completed
                          ? Colors.green
                          : theme.primaryColor,
                      decoration: appointment.completed 
                          ? TextDecoration.lineThrough 
                          : null,
                    ),
                  ),
                  if (appointment.completed) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'INGRESADO',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}