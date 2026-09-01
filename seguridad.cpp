#include "seguridad.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <openssl/evp.h>

using namespace std;

string leerDatoSeguro(const string& mensaje) {
    string entrada;
    cout << mensaje;
    cin.clear();
    if (cin.peek() == '\n') {
        cin.ignore(); 
    }
    
    getline(cin, entrada);

    if (entrada == "xxx") {
        throw CancelarOperacionException();
    }

    return entrada;
}

string aplicarHash(const string& input) {
    EVP_MD_CTX *mdctx = EVP_MD_CTX_new();
    unsigned char hash[EVP_MAX_MD_SIZE];
    unsigned int length = 0;

    if (mdctx == nullptr) {
        return "";
    }

    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestUpdate(mdctx, input.c_str(), input.size()) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    if (EVP_DigestFinal_ex(mdctx, hash, &length) != 1) {
        EVP_MD_CTX_free(mdctx);
        return "";
    }

    EVP_MD_CTX_free(mdctx);

    stringstream ss;
    for (unsigned int i = 0; i < length; ++i) {
        ss << hex << setw(2) << setfill('0') << static_cast<int>(hash[i]);
    }
    return ss.str();
}