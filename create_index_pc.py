from pinecone import Pinecone, ServerlessSpec

pc = Pinecone(api_key="pcsk_7YUacp_C11W6eeUY3QwFnCk2o6ku9c4Lqm8FbvMf8P69rzdwiMus8uYSgRooApk2iNzB5i")

pc.create_index(
    name="cloud-sentinel-index",
    dimension=1536, 
    metric="cosine",
    spec=ServerlessSpec(
        cloud="aws",
        region="ap-southeast-1",
    )
)

print("Index created successfully!")