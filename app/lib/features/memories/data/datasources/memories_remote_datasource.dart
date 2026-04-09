import '../../../../core/network/api_client.dart';
import '../models/memory_model.dart';

class MemoriesRemoteDatasource {
  final ApiClient _client;

  MemoriesRemoteDatasource(this._client);

  Future<List<MemoryModel>> getMemories(
    String deviceId, {
    String? category,
  }) async {
    final queryParams = <String, dynamic>{
      if (category != null) 'category': category, // ignore: use_null_aware_elements
    };
    final data = await _client.get(
      '/devices/$deviceId/memories',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final list = data as List;
    return list
        .map((json) => MemoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<MemoryModel> updateMemory(
    String id, {
    String? fact,
    String? category,
  }) async {
    final data = await _client.put('/memories/$id', data: {
      if (fact != null) 'fact': fact, // ignore: use_null_aware_elements
      if (category != null) 'category': category, // ignore: use_null_aware_elements
    });
    return MemoryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteMemory(String id) async {
    await _client.delete('/memories/$id');
  }
}
